variable "name" {
  description = "Name prefix for endpoint resources."
  type        = string
}

variable "region" {
  description = "AWS region (used to build service names like com.amazonaws.<region>.s3)."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the endpoints attach to."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block, used as the only allowed source for the endpoint security group."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnet IDs in which to place interface endpoint ENIs (one per AZ)."
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "Route tables to associate the S3 gateway endpoint with."
  type        = list(string)
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
