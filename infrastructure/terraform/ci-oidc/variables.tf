variable "project" {
  description = "Project name used for IAM role/policy naming and tagging"
  type        = string
  default     = "aws-security-findings-platform"
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub org/user that owns the repo allowed to assume these roles"
  type        = string
  default     = "Zach-Maestas"
}

variable "github_repo" {
  description = "GitHub repository name allowed to assume these roles (must match the actual repo name for the OIDC trust condition to match)"
  type        = string
  default     = "aws-security-findings-platform"
}

variable "tfstate_bucket" {
  description = "Name of the S3 bucket holding Terraform remote state — must match backend-state-init's bucket"
  type        = string
  default     = "aws-security-findings-platform-tfstate"
}

variable "tfstate_lock_table" {
  description = "Name of the DynamoDB table used for Terraform state locking — must match backend-state-init's table"
  type        = string
  default     = "terraform-lock"
}

variable "github_owner_id" {
  description = "GitHub's immutable numeric owner ID — GitHub embeds this in the OIDC sub claim alongside the owner name, so the trust condition needs it too"
  type        = string
  default     = "135179050"
}

variable "github_repo_id" {
  description = "GitHub's immutable numeric repository ID — GitHub embeds this in the OIDC sub claim alongside the repo name, so the trust condition needs it too"
  type        = string
  default     = "1149350582"
}
