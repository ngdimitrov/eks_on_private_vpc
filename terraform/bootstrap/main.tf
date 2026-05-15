# The GitHub OIDC IdP is account-level shared infra (only one per URL is
# allowed per account). By default this stack references the existing one and
# owns only the repo-scoped roles; flip manage_oidc_provider for a greenfield
# account. The thumbprint is fetched dynamically so it never goes stale when
# GitHub rotates its certificate chain.
data "tls_certificate" "github" {
  count = var.manage_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.manage_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.manage_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.manage_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# ---------------------------------------------------------------------------
# Plan role — read-only, assumable only by pull_request workflow runs.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_sub_prefix}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "gha-terraform-plan"
  description          = "GitHub Actions OIDC role: read-only terraform plan on PRs."
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "plan" {
  name   = "plan"
  role   = aws_iam_role.plan.id
  policy = file("${path.module}/../../docs/iam/plan-policy.json")
}

# ---------------------------------------------------------------------------
# Apply role — full deploy policy, assumable only by runs carrying the
# protected GitHub Environment claim (so the Environment's required reviewer
# gate sits in front of every credential issuance).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_sub_prefix}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "gha-terraform-apply"
  description          = "GitHub Actions OIDC role: terraform apply, gated by the ${var.github_environment} environment."
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "apply" {
  name   = "deploy"
  role   = aws_iam_role.apply.id
  policy = file("${path.module}/../../docs/iam/deploy-policy.json")
}
