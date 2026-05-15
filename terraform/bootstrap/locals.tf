locals {
  common_tags = merge(
    {
      Project   = "eks-private-demo"
      ManagedBy = "terraform"
      Stack     = "eks-on-private-vpc-bootstrap"
    },
    var.tags,
  )

  repo_sub_prefix = "repo:${var.github_owner}/${var.github_repo}"
}
