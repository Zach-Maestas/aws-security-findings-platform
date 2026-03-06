/*
==============================================================================
Root Configuration: Security Operations Pipeline
==============================================================================
Orchestrates all infrastructure modules for a secure, multi-tier web application:
- Network: VPC, subnets, routing, NAT gateways
- Secrets: Application database credentials
- Data: RDS PostgreSQL database
- ACM: TLS certificate for HTTPS
- App: ALB, ECS Fargate, ECR
- Security Ops: CloudTrail, GuardDuty, Security Hub, automated response

This configuration deploys a production-ready architecture with:
- Encrypted data at rest and in transit
- Least-privilege IAM and security groups
- Private subnet placement for sensitive resources
- Automated certificate management
==============================================================================
*/

# Network Module
module "network" {
  source                   = "./modules/network"
  project                  = var.project
  vpc_cidr                 = var.vpc_cidr
  azs                      = var.azs
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  permissions_boundary_arn = var.permissions_boundary_arn
}

# ACM Certificate
module "acm" {
  source         = "./modules/acm"
  project        = var.project
  domain_name    = var.domain_name
  hosted_zone_id = var.route53_zone_id
}

# Secrets Module
module "secrets" {
  source  = "./modules/secrets"
  project = var.project
}

# Data Module (RDS)
module "data" {
  source                = "./modules/data"
  project               = var.project
  vpc_id                = module.network.vpc_id
  private_db_subnet_ids = module.network.private_db_subnet_ids
  rds_sg_id             = module.network.rds_sg_id
}

# Application Module
module "app" {
  source                  = "./modules/app"
  project                 = var.project
  permissions_boundary_arn = var.permissions_boundary_arn
  vpc_id                 = module.network.vpc_id
  public_subnet_ids      = module.network.public_subnet_ids
  private_app_subnet_ids = module.network.private_app_subnet_ids
  private_db_subnet_ids  = module.network.private_db_subnet_ids
  alb_sg_id              = module.network.alb_sg_id
  ecs_tasks_sg_id        = module.network.ecs_tasks_sg_id
  certificate_arn        = module.acm.certificate_arn
  db_app_credentials_arn = module.secrets.db_app_credentials_secret_arn
  db_host                = module.data.db_host
  db_name                = module.data.db_name
  db_port                = module.data.db_port
  rds_master_secret_arn  = module.data.rds_master_secret_arn
  domain_name            = var.domain_name
  route53_zone_id        = var.route53_zone_id
}

# Security & Operations Module
module "security_ops" {
  source                  = "./modules/security-ops"
  project                 = var.project
  alert_email             = var.alert_email
  permissions_boundary_arn = var.permissions_boundary_arn
}
