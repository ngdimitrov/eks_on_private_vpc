module "vpc" {
  source = "./modules/vpc"

  name                 = var.cluster_name
  cidr_block           = var.vpc_cidr
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  cluster_name         = var.cluster_name
  tags                 = local.common_tags
}

module "vpc_endpoints" {
  source = "./modules/vpc-endpoints"
  count  = var.enable_vpc_endpoints ? 1 : 0

  name                    = var.cluster_name
  region                  = var.region
  vpc_id                  = module.vpc.vpc_id
  vpc_cidr_block          = module.vpc.vpc_cidr_block
  private_subnet_ids      = module.vpc.private_subnet_ids
  private_route_table_ids = module.vpc.private_route_table_ids
  tags                    = local.common_tags
}

module "bastion" {
  source = "./modules/bastion"
  count  = var.enable_bastion ? 1 : 0

  name           = "${var.cluster_name}-bastion"
  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr_block
  subnet_id      = module.vpc.private_subnet_ids[0]
  cluster_name   = var.cluster_name
  region         = var.region
  tags           = local.common_tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  # Length must be statically known at plan time (access entries use for_each).
  admin_role_arns = var.enable_bastion ? [module.bastion[0].iam_role_arn] : []

  tags = local.common_tags
}

# Bastion → private EKS API. Without this the kubectl call from the bastion
# times out at the cluster SG.
resource "aws_vpc_security_group_ingress_rule" "cluster_from_bastion" {
  count = var.enable_bastion ? 1 : 0

  security_group_id            = module.eks.cluster_security_group_id
  referenced_security_group_id = module.bastion[0].security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Bastion to private EKS API endpoint"

  tags = local.common_tags
}
