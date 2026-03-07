variable "project" {
  description = "The project name"
  type        = string
}

variable "alert_email" {
  description = "Email for SNS alerts"
  type        = string
  sensitive   = true
}

variable "permissions_boundary_arn" {
  description = "ARN of the permissions boundary to attach to IAM roles"
  type        = string
  default     = null
}