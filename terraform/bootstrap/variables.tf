variable "region" {
  description = "AWS region. Only used for the provider; the resources here (IAM + OIDC) are global."
  type        = string
  default     = "eu-west-1"
}

variable "github_owner" {
  description = "GitHub org or user that owns the repository."
  type        = string
  default     = "ngdimitrov"
}

variable "github_repo" {
  description = "GitHub repository name (without owner)."
  type        = string
  default     = "eks_on_private_vpc"
}

variable "github_environment" {
  description = "GitHub Environment name that gates the apply job. The apply role only trusts tokens carrying this environment claim."
  type        = string
  default     = "production"
}

variable "manage_oidc_provider" {
  description = "Create the GitHub OIDC provider. Only one provider per URL is allowed per account, so leave false (the default) when it already exists at the account level — the stack then references it as a data source and owns only the repo-scoped roles. Set true for a greenfield account."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}
