/*
==============================================================================
Security Groups: Network Access Control
==============================================================================
Implements least-privilege network security using security group references
instead of CIDR blocks for internal traffic.
==============================================================================
*/

# ALB Security Group - Public-facing load balancer
resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "Allow public HTTP and HTTPS traffic to Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project}-alb-sg" }
}

resource "aws_security_group_rule" "alb_in_http" {
  description       = "Allow HTTP from internet for HTTPS redirect"
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_in_https" {
  description       = "Allow HTTPS from internet"
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_out_to_ecs" {
  description              = "Allow ALB to forward traffic to ECS tasks on port 5000"
  type                     = "egress"
  security_group_id        = aws_security_group.alb.id
  from_port                = 5000
  to_port                  = 5000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
}

# ECS Tasks Security Group - Application containers
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project}-ecs-tasks-sg"
  description = "Allow ALB traffic to ECS tasks and egress to RDS and internet"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project}-ecs-tasks-sg" }
}

resource "aws_security_group_rule" "ecs_in_from_alb_5000" {
  description              = "Allow inbound from ALB on application port"
  type                     = "ingress"
  security_group_id        = aws_security_group.ecs_tasks.id
  from_port                = 5000
  to_port                  = 5000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "ecs_out_https" {
  description       = "Allow HTTPS outbound for ECR pulls and AWS API calls"
  type              = "egress"
  security_group_id = aws_security_group.ecs_tasks.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ecs_out_db" {
  description              = "Allow ECS tasks to connect to RDS PostgreSQL"
  type                     = "egress"
  security_group_id        = aws_security_group.ecs_tasks.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
}

# RDS Security Group - Database tier
resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "Allow PostgreSQL access from ECS tasks only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project}-rds-sg" }
}

resource "aws_security_group_rule" "rds_in_from_ecs" {
  description              = "Allow PostgreSQL inbound from ECS tasks only"
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
}
