output "region" {
  description = "AWS region the stack is deployed in."
  value       = var.region
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Private API server endpoint for the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider associated with the cluster (used for IRSA)."
  value       = module.eks.oidc_provider_arn
}

output "lb_controller_role_arn" {
  description = "IAM role ARN to annotate on the aws-load-balancer-controller ServiceAccount."
  value       = module.eks.lb_controller_role_arn
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (where nodes run)."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (NAT gateway only)."
  value       = module.vpc.public_subnet_ids
}

output "bastion_instance_id" {
  description = "Instance ID of the SSM-accessible bastion (empty if disabled)."
  value       = try(module.bastion[0].instance_id, "")
}

output "bastion_ssm_command" {
  description = "Copy-paste command to open an SSM session to the bastion."
  value = try(
    "aws ssm start-session --target ${module.bastion[0].instance_id} --region ${var.region}",
    "(bastion disabled)",
  )
}
