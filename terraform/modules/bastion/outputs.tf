output "instance_id" {
  description = "EC2 instance ID — pass to `aws ssm start-session --target ...`."
  value       = aws_instance.this.id
}

output "iam_role_arn" {
  description = "IAM role ARN attached to the bastion (mapped to cluster-admin via EKS access entry)."
  value       = aws_iam_role.this.arn
}

output "security_group_id" {
  description = "Security group ID attached to the bastion ENI."
  value       = aws_security_group.this.id
}
