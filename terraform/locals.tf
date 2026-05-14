locals {
  common_tags = merge(
    {
      Project   = var.cluster_name
      ManagedBy = "terraform"
      Stack     = "eks-on-private-vpc"
    },
    var.tags,
  )
}

data "aws_availability_zones" "available" {
  state = "available"
}
