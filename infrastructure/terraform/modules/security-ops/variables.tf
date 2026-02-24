variable "project" {
  description = "The project name"
  type        = string
}

variable "alert_email" {
  description = "Email for SNS alerts"
  type        = string
  sensitive   = true
}