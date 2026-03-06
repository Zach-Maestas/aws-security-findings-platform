/*
==============================================================================
Data Module: RDS PostgreSQL Database
==============================================================================
Provisions a PostgreSQL RDS instance with:
- Storage encryption at rest
- AWS-managed master password (stored in Secrets Manager)
- Private subnet placement (no public access)
- Automated backups with 7-day retention
==============================================================================
*/

# DB Subnet Group
resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = var.private_db_subnet_ids
  tags       = { Name = "${var.project}-db-subnet-group" }
}

# CloudWatch Log Group for PostgreSQL logs
resource "aws_cloudwatch_log_group" "rds_postgresql" {
  name              = "/aws/rds/instance/${var.project}-rds/postgresql"
  retention_in_days = 7
  tags              = { Name = "${var.project}-rds-logs" }
}

# Parameter Group for PostgreSQL logging
resource "aws_db_parameter_group" "this" {
  name   = "${var.project}-postgres-params"
  family = "postgres17"

  parameter {
    name  = "log_connections"
    value = 1
  }
  parameter {
    name  = "log_disconnections"
    value = 1
  }
  parameter {
    name  = "log_statement"
    value = "ddl" # detect only structural tampering
  }
}

# RDS Instance
resource "aws_db_instance" "this" {
  identifier                  = lower("${var.project}-rds")
  db_name                     = var.db_name
  engine                      = "postgres"
  engine_version              = "17"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  max_allocated_storage       = 100
  storage_type                = "gp3"
  storage_encrypted           = true
  username                    = var.db_admin_username
  manage_master_user_password = true
  port                        = var.db_port
  parameter_group_name        = aws_db_parameter_group.this.name
  db_subnet_group_name        = aws_db_subnet_group.this.name
  vpc_security_group_ids      = [var.rds_sg_id]
  multi_az                    = false # Cost optimization: single-AZ deployment
  publicly_accessible         = false
  backup_retention_period     = 7
  skip_final_snapshot         = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Name = "${var.project}-rds" }
}

