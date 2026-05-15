# CI/CD — GitHub Actions via OIDC

No long-lived AWS keys live in GitHub. Workflows mint a short-lived token from
GitHub's OIDC IdP and exchange it for STS credentials by assuming a role whose
trust policy is pinned to this repository.

## Trust model

| Role | Permissions | Trusted `sub` claim | Triggered by |
| --- | --- | --- | --- |
| `gha-terraform-plan` | [`docs/iam/plan-policy.json`](iam/plan-policy.json) — read-only | `repo:<owner>/<repo>:pull_request` | `pull_request` → `main` |
| `gha-terraform-apply` | [`docs/iam/deploy-policy.json`](iam/deploy-policy.json) — full deploy | `repo:<owner>/<repo>:environment:production` | `push` → `main` |

Both roles also require `aud = sts.amazonaws.com`. The `sub` conditions use
exact `StringEquals` (not a `repo:owner/repo:*` wildcard) so a token minted
for any other ref, workflow, or fork cannot assume either role.

The apply role only trusts tokens that carry the `environment:production`
claim. GitHub only injects that claim *after* the Environment's protection
rules pass — so the required-reviewer gate sits in front of every single
credential issuance, not just in front of the workflow step.

## One-time bootstrap (IaC, not ClickOps)

The two repo-scoped roles are themselves Terraform, in
[`terraform/bootstrap/`](../terraform/bootstrap). Applied once with the
least-privilege SSO profile (`EksProjectDeployer` has the IAM actions needed):

```bash
export AWS_PROFILE=<your-sso-profile>
aws sso login --sso-session <your-sso-session>

cd terraform/bootstrap
terraform init -backend-config=../backend.hcl
terraform apply -var-file=terraform.tfvars.example
```

The GitHub OIDC provider is **account-level shared infra** — only one per
URL is allowed per AWS account. By default this stack *references* the
existing provider (data source) and owns only the roles. For a greenfield
account that has no provider yet, set `manage_oidc_provider = true` and the
stack creates it (thumbprint fetched dynamically via `tls_certificate`).

State is the same S3 bucket as the main stack, different key
(`eks-on-private-vpc/bootstrap.tfstate`).

The role inline policies are sourced with `file()` from the same
`docs/iam/*.json` documents used to describe the SSO permission set — one
source of truth, no copy-paste drift between the human path and the CI path.

## Wire up GitHub

From the bootstrap outputs:

```bash
terraform -chdir=terraform/bootstrap output
```

Set on the repository:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `AWS_PLAN_ROLE_ARN` | `plan_role_arn` output |
| Secret | `AWS_APPLY_ROLE_ARN` | `apply_role_arn` output |
| Variable | `TF_STATE_BUCKET` | the `*-tfstate-*` bucket name |

Then create the **`production`** Environment (Settings → Environments) and add
yourself as a **required reviewer**. Without this Environment the apply job's
token never gets the `environment:production` claim and the assume-role call
is denied by design.

## Pipeline behaviour

- **PR → `main`**: `terraform plan -lock=false` with the read-only role; plan
  posted as a PR comment and job summary. Zero AWS mutations. Concurrency
  `tf-plan-<ref>` with cancel-in-progress supersedes stale plans.
- **push → `main`**: `terraform apply` with the deploy role, paused on the
  `production` Environment until the required reviewer approves. Concurrency
  `tf-apply` (no cancel) serializes applies on top of the S3 native lock.

Both jobs use `-var-file=environments/production.tfvars` — the committed
source of truth for what gets deployed, distinct from the illustrative
`terraform.tfvars.example`.

## Cost note

A full apply stands up EKS + a NAT gateway (~$5–10/day) and it stays up until
`terraform destroy`. The Environment approval gate is the safety valve against
an unintended expensive apply. For a portfolio account, tear down between
demos, or add a scheduled `terraform destroy` workflow.
