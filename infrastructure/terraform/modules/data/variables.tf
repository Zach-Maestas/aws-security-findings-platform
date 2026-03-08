variable "project" {
  description = "Project name"
  type        = string
}

variable "private_db_subnet_ids" {
  description = "Private database subnet IDs from the network layer"
  type        = list(string)
}

variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "appdb"
}

variable "db_admin_username" {
  description = "Database admin username"
  type        = string
  default     = "rds_master"
}

variable "db_port" {
  description = "Port number of the database"
  type        = number
  default     = 5432
}

variable "rds_sg_id" {
  description = "Security Group ID for the RDS instance"
  type        = string
}