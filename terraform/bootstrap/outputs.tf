output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider (created here or pre-existing)."
  value       = local.github_oidc_provider_arn
}

output "plan_role_arn" {
  description = "Set as the GitHub secret AWS_PLAN_ROLE_ARN (used by the PR plan job)."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Set as the GitHub secret AWS_APPLY_ROLE_ARN (used by the gated apply job)."
  value       = aws_iam_role.apply.arn
}
