variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "aws-security-findings-platform"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC"
  type        = string
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDRs"
  type        = list(string)
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "Private subnets reserved for the future application/compute tier"
  type        = list(string)
}

variable "private_db_subnet_cidrs" {
  description = "Private subnets reserved for the future data tier"
  type        = list(string)
}
