# Bootstrap params consumed by scripts/bootstrap-bastion.sh on the bastion.
# Stored as SecureString so they don't show up in describe-parameters without
# decrypt permission.

resource "aws_ssm_parameter" "lb_controller_role_arn" {
  name        = "/${var.cluster_name}/bootstrap/lb-controller-role-arn"
  description = "IRSA role ARN for the AWS Load Balancer Controller"
  type        = "SecureString"
  value       = module.eks.lb_controller_role_arn
  tags        = local.common_tags
}

resource "aws_ssm_parameter" "vpc_id" {
  name        = "/${var.cluster_name}/bootstrap/vpc-id"
  description = "VPC ID — passed to the LB Controller Helm chart as vpcId"
  type        = "SecureString"
  value       = module.vpc.vpc_id
  tags        = local.common_tags
}
