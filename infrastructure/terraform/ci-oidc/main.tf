/*
==============================================================================
CI/CD OIDC Module: GitHub Actions Authentication
==============================================================================
Provisions OIDC federation for GitHub Actions CI/CD:
- OIDC identity provider for GitHub Actions
- IAM role assumable by GitHub Actions workflows
- Scoped permissions for ECR, ECS, S3, and DynamoDB
==============================================================================
*/

provider "aws" {
    region = "us-east-1"
}

locals {
    region     = "us-east-1"
    account_id = "124355647999"
    project    = "secops-pipeline"
}

# GitHub Actions OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "1b511abead59c6ce207077c0bf0e0043b1382612",
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]

  tags = {
    Name = "github-actions-oidc-provider"
  }
}

# GitHub Actions IAM Role
resource "aws_iam_role" "github_actions" {
  name = "GitHubActionsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:Zach-Maestas/aws-security-ops-pipeline:*"
          }
        }
      }
    ]
  })
}

# GitHub Actions Deploy Policy Document
data "aws_iam_policy_document" "github_actions_deploy" {
    statement {
        sid    = "ECRAuth"
        effect = "Allow"
        actions = [
            "ecr:GetAuthorizationToken"
        ]
        resources = ["*"]
    }

    # ECR push to specific repository
    statement {
        sid    = "ECRPush"
        effect = "Allow"
        actions = [
            "ecr:PutImage",
            "ecr:BatchCheckLayerAvailability",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
            "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer"
        ]
        resources = [
            "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.project}-*"
        ]
    }

    # ECS service updates
    statement {
        sid    = "ECSService"
        effect = "Allow"
        actions = [
            "ecs:UpdateService",
            "ecs:DescribeServices"
        ]
        resources = [
            "arn:aws:ecs:${local.region}:${local.account_id}:service/${local.project}-ecs-cluster/*"
        ]
    }

    # S3 bucket listing for Terraform state
    statement {
        sid    = "S3BucketList"
        effect = "Allow"
        actions = [
            "s3:ListBucket"
        ]
        resources = [
            "arn:aws:s3:::secops-pipeline-tfstate"
        ]
    }

    # S3 object access for Terraform state
    statement {
        sid    = "S3ObjectAccess"
        effect = "Allow"
        actions = [
            "s3:GetObject",
            "s3:PutObject"
        ]
        resources = [
            "arn:aws:s3:::secops-pipeline-tfstate/*"
        ]
    }

    # DynamoDB for Terraform state locking
    statement {
        sid    = "DynamoDBStateLock"
        effect = "Allow"
        actions = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:DeleteItem"
        ]
        resources = [
            "arn:aws:dynamodb:${local.region}:${local.account_id}:table/terraform-lock"
        ]
    }
}

# IAM Policy for GitHub Actions deployment
resource "aws_iam_policy" "github_actions_deploy_policy" {
    name        = "${local.project}-github-actions-deploy-policy"
    description = "Policy to allow GitHub Actions to run the deployment pipeline"
    policy      = data.aws_iam_policy_document.github_actions_deploy.json
}

# Policy Attachment for GitHub Actions deployment access
resource "aws_iam_role_policy_attachment" "github_actions_deploy_policy_attach" {
    role       = aws_iam_role.github_actions.name
    policy_arn = aws_iam_policy.github_actions_deploy_policy.arn
}