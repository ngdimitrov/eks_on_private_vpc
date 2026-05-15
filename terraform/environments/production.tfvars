# Production environment values consumed by the CD pipeline (.github/workflows/cd.yml).
# This is the committed source of truth for what `terraform apply` deploys —
# distinct from terraform.tfvars.example, which stays purely illustrative.
region             = "eu-west-1"
cluster_name       = "eks-private-demo"
kubernetes_version = "1.35"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 2
node_max_size       = 4

enable_vpc_endpoints = true
enable_bastion       = true

tags = {
  Owner       = "platform-eng"
  Environment = "production"
}
