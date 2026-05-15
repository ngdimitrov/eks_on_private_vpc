# EKS on a Private VPC

[![CI](https://github.com/ngdimitrov/eks_on_private_vpc/actions/workflows/ci.yml/badge.svg)](https://github.com/ngdimitrov/eks_on_private_vpc/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Terraform stack for an EKS cluster with control plane and workers in private subnets, single NAT for egress, and VPC endpoints for S3/ECR/SSM. An SSM-only bastion lets you run `kubectl` against the private API without a VPN.

## Prerequisites

- Terraform `>= 1.10` (`use_lockfile` for native S3 state locking)
- AWS CLI `>= 2.13` + [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- AWS credentials via **IAM Identity Center (SSO)** with a custom least-privilege permission set sourced from [`docs/iam/deploy-policy.json`](docs/iam/deploy-policy.json) on a dedicated demo account (4h session, no long-lived keys on disk). Standard SDK chain (`AWS_PROFILE` / env vars) also works. See [Credentials & secrets](#credentials--secrets).
- Region: `eu-west-1` by default (override in `terraform.tfvars`)

## Deploy

```bash
# 0. Authenticate. This project uses IAM Identity Center (SSO) — short-lived
#    4h STS credentials, no keys on disk. See docs/iam/README.md for how the
#    least-privilege permission set was created.
aws sso login --sso-session <your-sso-session>
export AWS_PROFILE=<your-sso-profile>
aws sts get-caller-identity   # expect assumed-role/AWSReservedSSO_EksProjectDeployer_*/<you>

# 1. One-time per account: create the S3 bucket that holds the Terraform state
#    (versioning ON, encrypted, public access blocked, native S3 locking).
./scripts/bootstrap-state-bucket.sh

# 2. Initialize with the generated backend.hcl and apply
cd terraform
terraform init -backend-config=backend.hcl
terraform apply         # ~15-20 min (EKS control plane + node group are the slow steps)
```

> Reviewers without SSO: set `AWS_PROFILE` (or `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) to any principal holding the [`docs/iam/deploy-policy.json`](docs/iam/deploy-policy.json) permissions and skip step 0. The Terraform code is auth-mechanism agnostic.

State and lock file live in `s3://<prefix>-tfstate-<account>/eks-on-private-vpc/` — no DynamoDB table needed (Terraform `>= 1.10` `use_lockfile = true`). Defaults: CIDR `10.0.0.0/16`, two AZs, 2 public + 2 private subnets, 1 NAT, 2× `t3.medium` nodes, K8s 1.35. Toggle `enable_vpc_endpoints` / `enable_bastion` in `terraform.tfvars.example` to opt out.

## Validate

```bash
# 1. SSM into the bastion (no VPN, no SSH key)
$(terraform -chdir=terraform output -raw bastion_ssm_command)

# 2. Pull the repo onto the bastion
sudo dnf -y install git
git clone https://github.com/ngdimitrov/eks_on_private_vpc.git ~/eks-private-vpc
cd ~/eks-private-vpc

# 3. Run the validation script (installs LB Controller, deploys nginx, curls the internal NLB)
source /etc/profile.d/eks.sh
./scripts/bootstrap-bastion.sh
```

The script ends with `Validation complete.` and prints:
- `kubectl get nodes -o wide` — 2 Ready nodes, `EXTERNAL-IP` empty
- `kubectl get pods -l app=nginx -o wide` — pod IPs in `10.0.10.0/24` / `10.0.11.0/24`
- `curl http://<internal-nlb>/` from bastion — `200 OK` + nginx welcome page; from your laptop the same curl times out (proof it's internal)

## Teardown

The AWS LB Controller-managed NLB owns ENIs in the private subnets, so delete the K8s objects before `terraform destroy`:

```bash
# on the bastion
kubectl delete -f manifests/nginx-internal-nlb.yaml
helm uninstall aws-load-balancer-controller -n kube-system

# on your laptop
terraform -chdir=terraform destroy
```

## Credentials & secrets

Nothing about credentials or secrets is stored in the repo. The deployment uses only AWS-native mechanisms.

### What this take-home does

**IAM Identity Center (SSO)** with a custom least-privilege permission set sourced from [`docs/iam/deploy-policy.json`](docs/iam/deploy-policy.json) on a dedicated demo account. The policy is scoped to exactly what this stack provisions (VPC + EKS + IAM + KMS + Logs + SSM + S3 state bucket scoped via the `*-tfstate-*` ARN pattern) — roughly 90% narrower than `AdministratorAccess`, no Organizations / Billing / Account / cross-service Identity Center reach.

Daily flow: `aws sso login --sso-session <name>` → 4h STS session cached under `~/.aws/sso/cache/` → Terraform / kubectl / SDKs pick it up transparently via `AWS_PROFILE`. No long-lived keys on disk, MFA enforced at SSO login, sessions expire automatically.

Reviewers without SSO can still use the standard SDK credential chain (`~/.aws/credentials` / env vars) — the Terraform code is auth-mechanism agnostic.

### CI/CD — GitHub OIDC, no static keys

`terraform plan` runs on every PR (read-only role) and `terraform apply` runs on push to `main` behind a required-reviewer GitHub Environment, both via GitHub OIDC federation — zero long-lived keys in GitHub. The OIDC provider and the two repo-pinned roles are themselves IaC in [`terraform/bootstrap/`](terraform/bootstrap); role policies are sourced from the same [`docs/iam/`](docs/iam) JSON used for the SSO permission set. Full design and setup: [`docs/cicd.md`](docs/cicd.md).

### What I would do for production

- **Separate AWS accounts per environment** under AWS Organizations (dev / stage / prod), with the same permission set materialized in each. Blast radius of any deploy stays inside one account.
- **Permissions boundary** on the CI apply role so a compromised pipeline cannot escalate by creating roles with broader policies than the boundary allows.

### Other credential boundaries in the stack

- **Cluster ↔ AWS API auth (pods)** — IAM Roles for Service Accounts (IRSA). The AWS Load Balancer Controller's SA trusts the cluster's OIDC provider and a fixed subject (`system:serviceaccount:kube-system:aws-load-balancer-controller`). No long-lived keys, no shared service-account tokens.
- **Cluster ↔ Kubernetes API auth (humans)** — EKS access entries map IAM principal ARNs to `AmazonEKSClusterAdminPolicy`. The cluster creator and the bastion role get admin; no `aws-auth` ConfigMap to drift, no kubeconfig with embedded credentials.
- **Bastion access** — SSM Session Manager only. No SSH keys are generated, no inbound ports, no public IP. The bastion's IAM role has `AmazonSSMManagedInstanceCore` plus a narrow inline policy (`eks:DescribeCluster`, `ssm:GetParameter*` on `/<cluster>/bootstrap/*`, `kms:Decrypt` on `alias/aws/ssm`).
- **Bootstrap parameters** (LB Controller role ARN, VPC ID) — published by Terraform to SSM Parameter Store as `SecureString` and read by `scripts/bootstrap-bastion.sh`. No copy-paste between machines.
- **Kubernetes secrets** — envelope-encrypted with a customer-managed KMS key. The key policy grants `kms:*` only to the account root + CloudWatch Logs service (scoped via `kms:EncryptionContext`).
- **Terraform state** — stored in S3 with **SSE-KMS** (customer-managed key, rotation on), versioning ON, public access blocked, a bucket policy denying non-TLS access, and native `use_lockfile` locking. The state contains resource attributes (some sensitive); rotate state-bucket access through IAM, not bucket policies.
- **Secret rotation** — no static secrets exist in this stack: SSO/STS short-lived credentials for humans; IRSA short-lived tokens for pods; SSM agent uses temporary credentials from the instance role. KMS key rotation is enabled.
- **CI/CD ↔ AWS** — GitHub OIDC federation, no static keys in GitHub. Static-analysis jobs (`ci.yml`) need no AWS access; the `cd.yml` plan/apply jobs assume repo-pinned, `sub`-scoped roles for the duration of one job. See [`docs/cicd.md`](docs/cicd.md).

## Bonus — VPC endpoints

`enable_vpc_endpoints = true` (default) provisions the four required endpoints plus two extras needed by SSM Session Manager:

| Service | Type |
| --- | --- |
| `com.amazonaws.<region>.s3` | Gateway (no ENI) |
| `com.amazonaws.<region>.ecr.api` | Interface |
| `com.amazonaws.<region>.ecr.dkr` | Interface |
| `com.amazonaws.<region>.ssm` | Interface |
| `com.amazonaws.<region>.ssmmessages` | Interface (SSM data plane) |
| `com.amazonaws.<region>.ec2messages` | Interface (SSM agent heartbeat) |

All interface endpoints sit in both private subnets behind an SG that accepts `tcp/443` only from the VPC CIDR; private DNS is enabled.

## Known limitations / assumptions

- **Single NAT gateway** by design. For prod: one per AZ.
- **Private-only EKS API.** `kubectl` runs from the bastion; no public endpoint. To flip it, set `endpoint_public_access = true` + `public_access_cidrs` in `modules/eks/cluster.tf`.
- **Remote state in S3** is required (committed `backend.tf`). The bootstrap script creates the bucket idempotently; bucket name is account-derived so the same code works for any reviewer without edits.
- **LB Controller installed via Helm from the bastion** (not Terraform's `helm` provider) because the Terraform host runs outside the VPC and cannot reach the private API.
- **LB Controller policy + Helm chart are version-coupled.** Vendored policy is upstream `v2.13.4`; chart is `1.13.4`. Bump them together.
- **Public ECR pulls still traverse NAT** — `ecr.{api,dkr}` endpoints only short-circuit private ECR. Mirror images to private ECR if you need a fully air-gapped path.
- **Cluster creator gets cluster-admin** via `bootstrap_cluster_creator_admin_permissions = true`.
- **KMS key has a 7-day deletion window** for easy demo teardown — bump to 30 for prod.

## How this addresses the evaluation criteria

- **Correctness** — All requirements covered; full deploy + nginx-on-internal-NLB validated end-to-end on AWS. CI re-runs fmt/validate/tflint on every commit; checkov **hard-fails on HIGH/CRITICAL** and tfsec hard-fails at `--minimum-severity HIGH` (lower-severity by-design items stay reported but non-blocking).
- **Code structure** — Four submodules (`vpc`, `vpc-endpoints`, `eks`, `bastion`), each with its own `versions.tf` and a narrow input/output interface. The `eks` module is split by concern (`cluster.tf`, `iam.tf`, `oidc.tf`, `security-groups.tf`, `node-group.tf`, `access-entries.tf`).
- **Security defaults** — Both public and private subnets have `map_public_ip_on_launch = false` (nothing launches in public — NAT uses an EIP), node group has no `remote_access`, EKS API is private, IMDSv2 required with **node IMDS hop limit 1** (pods can't steal the node role — they must use IRSA), KMS-encrypted secrets + CW logs, **VPC Flow Logs** (ALL traffic, KMS-encrypted CW group), node SG egress scoped to **443 + in-VPC** (no all-protocol `0.0.0.0/0`), control-plane logs include `api/audit/authenticator/controllerManager/scheduler`, locked-down default VPC SG, IRSA scoped to one ServiceAccount, modern EKS access entries (no `aws-auth` ConfigMap).
- **README quality** — This file. Reviewer's path is: install prerequisites → `terraform apply` → SSM in → run one script → see `Validation complete.`
- **Bonus VPC endpoints** — All four required services + the two SSM data-plane endpoints needed for `aws ssm start-session` to work without internet. SG tightly scoped to VPC CIDR.
