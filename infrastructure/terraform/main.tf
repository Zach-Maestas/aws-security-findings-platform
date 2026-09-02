/*
==============================================================================
Root Configuration: AWS Network Foundation
==============================================================================
Baseline network layer for the project: a VPC across two AZs with public
subnets, and empty private "app" and "db" subnet tiers reserved for the
compute and data layers, which are currently being redesigned.
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
}
