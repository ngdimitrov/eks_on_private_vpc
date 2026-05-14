# Static int keys so for_each works with apply-time ARNs.
locals {
  admin_role_arns = { for idx, arn in var.admin_role_arns : tostring(idx) => arn }
}

resource "aws_eks_access_entry" "admin" {
  for_each = local.admin_role_arns

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = local.admin_role_arns

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
