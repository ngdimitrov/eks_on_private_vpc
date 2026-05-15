# IAM artifacts

This stack is deployed with **short-lived credentials only**. There is no IAM
user and no long-lived access key anywhere in the workflow.

## Files

| File | Purpose |
| --- | --- |
| [`deploy-policy.json`](deploy-policy.json) | Least-privilege permissions policy — exactly the actions this Terraform stack needs (VPC + EKS + IAM + KMS + Logs + SSM + S3 state scoped via the `*-tfstate-*` ARN pattern). Used as the **inline policy** of the SSO permission set. |

## How the SSO permission set was created

Identity Center directory, home region `eu-west-1`, MFA enforced at first login.

1. **Permission sets → Create permission set → Custom permission set**
   - Name: `EksProjectDeployer`
   - Session duration: **4 hours**
   - Inline policy: the full contents of [`deploy-policy.json`](deploy-policy.json)
     (≈4.7 KB — well under the 10,240-char Identity Center inline limit)
2. **AWS accounts → \<account\> → Assign users or groups** → assign the user to
   `EksProjectDeployer`.
3. Verified end-to-end with `terraform init` + `terraform plan` against the
   real account (`Plan: 62 to add, 0 to change, 0 to destroy`, zero
   `AccessDenied`).
4. **`AdministratorAccess` assignment removed** — the user is left with only
   `EksProjectDeployer`. The `AdministratorAccess` permission set itself is
   kept *unassigned* as a break-glass option (re-assign via console for a few
   minutes if a missing write action ever surfaces during `apply`, capture it,
   add it here, remove again).

## Local config

`~/.aws/config` (no `~/.aws/credentials` entry — SSO caches tokens under
`~/.aws/sso/cache/`):

```ini
[sso-session my-sso]
sso_start_url = https://<your-portal>.awsapps.com/start
sso_region    = eu-west-1
sso_registration_scopes = sso:account:access

[profile eks]
sso_session    = my-sso
sso_account_id = <account-id>
sso_role_name  = EksProjectDeployer
region         = eu-west-1
```

Daily use: `aws sso login --sso-session my-sso` → `export AWS_PROFILE=eks`.
Terraform / kubectl / SDKs read the cached STS session transparently.

## Note on `deploy-policy.json` scope

`plan` exercises only read APIs (`Describe*` / `Get*` / `List*`); the
create/delete/modify actions are validated by a full `apply`. The policy was
audited against every resource type in `terraform/modules/`, including
`iam:CreateServiceLinkedRole` (scoped via `iam:AWSServiceName` to
`eks.amazonaws.com` and `eks-nodegroup.amazonaws.com`) which a first-time
`apply` on a fresh account needs before EKS can materialize its
service-linked roles.
