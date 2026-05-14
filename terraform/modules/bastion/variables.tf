variable "name" {
  description = "Name prefix for bastion resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block — used to scope the bastion's DNS egress to the in-VPC resolver."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID for the bastion ENI."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name (used by user-data to write kubeconfig)."
  type        = string
}

variable "region" {
  description = "AWS region (used by user-data)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion."
  type        = string
  default     = "t3.micro"
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
