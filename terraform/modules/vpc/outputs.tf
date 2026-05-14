output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "Primary CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, ordered by AZ."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, ordered by AZ."
  value       = aws_subnet.private[*].id
}

output "private_route_table_ids" {
  description = "Route table IDs for the private subnets (used to attach the S3 gateway endpoint)."
  value       = [aws_route_table.private.id]
}
