variable "project" {
  description = "The project name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDRs"
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private subnets hosting application instances"
  type        = list(string)
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private subnets hosting databases"
  type        = list(string)
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
}
