/*
==============================================================================
DB Init Task: Database Initialization Infrastructure
==============================================================================
Provisions ECS task definition for one-time database initialization:
- Creates schema and tables
- Creates application database user with least-privilege permissions
- Sets password from Secrets Manager
- Seeds initial data
This task is run once after infrastructure deployment.
==============================================================================
*/

# ECS Execution Role for DB Init Task
resource "aws_iam_role" "ecs_exec_db_init" {
  name = "${var.project}-ecs-exec-db-init-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })


  tags = {
    Name = "${var.project}-ecs-exec-db-init-role"
  }
}

# IAM Policy to allow ECS Task to read RDS master secret from Secrets Manager
data "aws_iam_policy_document" "db_init_exec_secrets" {
  statement {
    sid    = "ReadSecretsForInjection"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      var.rds_master_secret_arn,
      var.db_app_credentials_arn
    ]
  }
}

# Policy Attachment for ECS DB Init Execution Role
resource "aws_iam_role_policy_attachment" "ecs_exec_db_init_policy_attach" {
  role       = aws_iam_role.ecs_exec_db_init.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Policy for DB Init Secrets access
resource "aws_iam_policy" "db_init_secrets_policy" {
  name        = "${var.project}-db-init-secrets-policy"
  description = "Policy to allow ECS task to read DB admin credentials from Secrets Manager"
  policy      = data.aws_iam_policy_document.db_init_exec_secrets.json
}

# Policy Attachment for DB Init Secrets access
resource "aws_iam_role_policy_attachment" "db_init_secrets_policy_attach" {
  role       = aws_iam_role.ecs_exec_db_init.name
  policy_arn = aws_iam_policy.db_init_secrets_policy.arn
}

# ECR Repository (DB Init)
resource "aws_ecr_repository" "ecr_db_init_repo" {
  name         = "${var.project}-db-init-repo"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project}-db-init-repo"
  }
}

# ECS Task Definition for DB Initialization
resource "aws_ecs_task_definition" "db_init" {
  family                   = "${var.project}-db-init-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_exec_db_init.arn
  container_definitions = jsonencode([
    {
      name  = "db-init-container"
      image = "${aws_ecr_repository.ecr_db_init_repo.repository_url}:${var.db_init_image_tag}"

      environment = [
        {
          name  = "PGHOST"
          value = var.db_host
        },
        {
          name  = "PGDATABASE"
          value = var.db_name
        },
        {
          name  = "PGPORT"
          value = tostring(var.db_port)
        }
      ]

      secrets = [
        {
          name      = "PGUSER"
          valueFrom = "${var.rds_master_secret_arn}:username::"
        },
        {
          name      = "PGPASSWORD"
          valueFrom = "${var.rds_master_secret_arn}:password::"
        },
        {
          name      = "APP_DB_USERNAME"
          valueFrom = "${var.db_app_credentials_arn}:username::"
        },
        {
          name      = "APP_DB_PASSWORD"
          valueFrom = "${var.db_app_credentials_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_db_init_logs_group.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# CloudWatch Log group for db-init logs
resource "aws_cloudwatch_log_group" "ecs_db_init_logs_group" {
  name              = "/ecs/${var.project}-db-init"
  retention_in_days = 7

  tags = {
    Name = "${var.project}-ecs-db-init-logs"
  }
}