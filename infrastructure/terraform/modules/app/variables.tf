variable "project" {
  description = "The project name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (for ALB)"
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "List of private subnet IDs (for ECS tasks)"
  type        = list(string)
}

variable "certificate_arn" {
  description = "The ARN of the ACM certificate to use with the ALB"
  type        = string
}

variable "db_app_credentials_arn" {
  description = "ARN of the Secrets Manager secret for DB app credentials"
  type        = string
}

variable "alb_sg_id" {
  description = "Security Group ID for the ALB"
  type        = string
}

variable "ecs_tasks_sg_id" {
  description = "Security Group ID for the ECS tasks"
  type        = string
}

variable "db_host" {
  description = "Hostname of the database"
  type        = string
}

variable "db_name" {
  description = "Name of the database"
  type        = string
}

variable "db_port" {
  description = "Port number of the database"
  type        = number
}

variable "rds_master_secret_arn" {
  description = "ARN of the RDS master secret"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the Route 53 A record (e.g. api.example.com)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 Hosted Zone ID for DNS record creation"
  type        = string
}

variable "api_image_tag" {
  description = "Docker image tag for the API container"
  type        = string
  default     = "latest" # replace with SHA hash from pipeline deploy
}

variable "db_init_image_tag" {
  description = "Docker image tag for the DB Init container"
  type        = string
  default     = "latest"
}

variable "api_desired_count" {
  description = "Desired number of API tasks to run (0 for initial deploy, 1 after db_init)"
  type        = number
  default     = 0
}

variable "permissions_boundary_arn" {
  description = "ARN of the permissions boundary to attach to IAM roles"
  type        = string
  default     = null
}