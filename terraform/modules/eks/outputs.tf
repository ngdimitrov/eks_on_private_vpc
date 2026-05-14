output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Private API server endpoint URL."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group ID (attached to control plane and node ENIs)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "lb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller (annotate the SA with this)."
  value       = aws_iam_role.lb_controller.arn
}
