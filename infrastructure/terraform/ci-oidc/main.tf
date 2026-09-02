/*
==============================================================================
CI/CD OIDC Module: GitHub Actions Authentication
==============================================================================
Provisions OIDC federation for GitHub Actions CI/CD:
- OIDC identity provider for GitHub Actions
- Plan role: read-only, used on PR workflows for scans + terraform plan
- Deploy role: provisioning access with permissions boundary, used on merge to main

Note: This module's state is stored locally. It exists as a separate bootstrap
workspace that must be applied before the main infrastructure. OIDC least privilege
isn't strictly required for a personal project, but demonstrates production
practices: prevents giving root access to GitHub Actions, prevents privilege escalation, 
and prevents stored AWS credentials.

Permissions trimmed 2026-09: the security-ops module (CloudTrail, GuardDuty,
Security Hub, EventBridge/Lambda remediation, SNS alerting) and the app/data
layers were removed during a backend-focused rescope. The deploy role's
security-ops-only statements (CloudTrail, GuardDuty, SecurityHub, Lambda,
EventBridge, SNS, and the S3 statement that existed only for the CloudTrail
logs bucket) were removed rather than left dangling and unused. Route53, ACM,
and KMS were left in place since the app layer (and its ALB/ACM cert) is
expected to return soon and would need them again immediately.

Renamed 2026-09 (secops-pipeline -> aws-security-findings-platform): project
name, GitHub owner/repo, the state bucket/lock table, and the AWS account ID
are now all variables/data lookups instead of hardcoded locals, so a future
rename or fork only touches terraform.tfvars — no code edit required.
==============================================================================
*/

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  github_sub = "repo:${var.github_owner}/${var.github_repo}"

  # Constructed ARN to break circular dependency (boundary references itself)
  permissions_boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project}-deploy-permissions-boundary"
}

# =============================================================================
# OIDC Identity Provider
# =============================================================================

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
    Name = "${var.project}-oidc-provider"
  }
}

# =============================================================================
# Shared Policy: Terraform State Access (both roles need this)
# =============================================================================

data "aws_iam_policy_document" "terraform_state" {
  statement {
    sid    = "S3BucketList"
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket}"
    ]
  }

  statement {
    sid    = "S3ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket}/*"
    ]
  }

  statement {
    sid    = "DynamoDBStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    resources = [
      "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.tfstate_lock_table}"
    ]
  }
}

resource "aws_iam_policy" "terraform_state" {
  name        = "${var.project}-terraform-state-access"
  description = "S3 and DynamoDB access for Terraform remote state"
  policy      = data.aws_iam_policy_document.terraform_state.json

  tags = {
    Name = "${var.project}-terraform-state-access"
  }
}

# =============================================================================
# Plan Role: PR workflows (scan + terraform plan)
# =============================================================================

resource "aws_iam_role" "github_actions_plan" {
  name = "${var.project}-github-actions-plan"

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
            "token.actions.githubusercontent.com:sub" = "${local.github_sub}:pull_request"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project}-github-actions-plan"
  }
}

# Plan role: read-only access for terraform plan
data "aws_iam_policy_document" "plan_permissions" {
  # Read-only across services terraform plan needs to inspect
  statement {
    sid    = "ReadOnlyForPlan"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:GetAuthorizationToken",
      "rds:Describe*",
      "rds:ListTagsForResource",
      "s3:Get*",
      "s3:ListBucket",
      "iam:Get*",
      "iam:List*",
      "secretsmanager:Describe*",
      "secretsmanager:GetResourcePolicy",
      "elasticloadbalancing:Describe*",
      "logs:Describe*",
      "logs:GetLogEvents",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
      "cloudtrail:Describe*",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:ListTags",
      "cloudtrail:GetEventSelectors",
      "cloudtrail:GetInsightSelectors",
      "guardduty:Get*",
      "guardduty:List*",
      "securityhub:Describe*",
      "securityhub:Get*",
      "lambda:Get*",
      "lambda:List*",
      "events:Describe*",
      "events:List*",
      "sns:Get*",
      "sns:List*",
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets",
      "acm:Describe*",
      "acm:List*",
      "kms:Describe*",
      "kms:List*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "plan_permissions" {
  name        = "${var.project}-github-actions-plan-permissions"
  description = "Read-only permissions for terraform plan in PR workflows"
  policy      = data.aws_iam_policy_document.plan_permissions.json

  tags = {
    Name = "${var.project}-github-actions-plan-permissions"
  }
}

resource "aws_iam_role_policy_attachment" "plan_state" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = aws_iam_policy.terraform_state.arn
}

resource "aws_iam_role_policy_attachment" "plan_permissions" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = aws_iam_policy.plan_permissions.arn
}

# =============================================================================
# Deploy Role: merge-to-main workflows (terraform apply + ECR push)
# =============================================================================

resource "aws_iam_role" "github_actions_deploy" {
  name = "${var.project}-github-actions-deploy"

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
            "token.actions.githubusercontent.com:sub" = "${local.github_sub}:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  permissions_boundary = aws_iam_policy.deploy_permissions_boundary.arn

  tags = {
    Name = "${var.project}-github-actions-deploy"
  }
}

# Deploy role: provisioning permissions for terraform apply
data "aws_iam_policy_document" "deploy_permissions" {
  # ECR + ECS global (actions that don't support resource-level ARNs)
  statement {
    sid    = "ECRECSGlobal"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecs:CreateCluster",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECR"
    effect = "Allow"
    actions = [
      "ecr:PutImage", "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:Describe*", "ecr:List*",
      "ecr:CreateRepository", "ecr:DeleteRepository",
      "ecr:TagResource", "ecr:PutLifecyclePolicy", "ecr:PutImageTagMutability"
    ]
    resources = [
      "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.project}-*"
    ]
  }

  # ECS: manage clusters, services, task definitions
  statement {
    sid     = "ECS"
    effect  = "Allow"
    actions = ["ecs:*"]
    resources = [
      "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.project}-*",
      "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${var.project}-*/*",
      "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.project}-*:*",
      "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:task/${var.project}-*/*"
    ]
  }

  # VPC + Networking
  statement {
    sid    = "Networking"
    effect = "Allow"
    actions = [
      "ec2:*Vpc*", "ec2:*Subnet*", "ec2:*RouteTable*", "ec2:*Route",
      "ec2:*InternetGateway*", "ec2:*NatGateway*", "ec2:*SecurityGroup*",
      "ec2:*Address*", "ec2:*NetworkAcl*", "ec2:*Tags*", "ec2:*FlowLog*",
      "ec2:Describe*", "ec2:AllocateAddress", "ec2:ReleaseAddress"
    ]
    resources = ["*"]
  }

  # RDS
  statement {
    sid     = "RDS"
    effect  = "Allow"
    actions = ["rds:*"]
    resources = [
      "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${var.project}-*",
      "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:subgrp:${var.project}-*",
      "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:pg:${var.project}-*"
    ]
  }

  statement {
    sid       = "RDSDescribe"
    effect    = "Allow"
    actions   = ["rds:Describe*"]
    resources = ["*"]
  }

  # ALB
  statement {
    sid    = "ALB"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:*"
    ]
    resources = ["*"]
  }

  # IAM: create roles and policies for ECS tasks, Lambda
  statement {
    sid    = "IAMRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole",
      "iam:GetRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:TagRole", "iam:UntagRole",
      "iam:PassRole",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy",
      "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion", "iam:TagPolicy",
      "iam:ListInstanceProfilesForRole"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project}-*"
    ]
  }

  # Secrets Manager
  statement {
    sid    = "SecretsManager"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret",
      "secretsmanager:Describe*", "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue", "secretsmanager:TagResource",
      "secretsmanager:GetResourcePolicy", "secretsmanager:PutResourcePolicy"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}-*",
      "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/*",
      "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!*"
    ]
  }

  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy", "logs:TagResource",
      "logs:ListTagsLogGroup", "logs:ListTagsForResource"
    ]
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:*${var.project}*",
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:*${var.project}*:*"
    ]
  }

  statement {
    sid       = "CloudWatchLogsDescribe"
    effect    = "Allow"
    actions   = ["logs:Describe*"]
    resources = ["*"]
  }

}

resource "aws_iam_policy" "deploy_permissions" {
  name        = "${var.project}-github-actions-deploy-permissions"
  description = "Infrastructure provisioning permissions for terraform apply"
  policy      = data.aws_iam_policy_document.deploy_permissions.json

  tags = {
    Name = "${var.project}-github-actions-deploy-permissions"
  }
}

# =============================================================================
# Deploy Role: Security operations permissions (split to stay under 6144 limit)
# =============================================================================
# Trimmed 2026-09: security-ops (CloudTrail, GuardDuty, SecurityHub, Lambda,
# EventBridge, SNS) and its S3 statement were removed — that infrastructure
# no longer exists in this repo. Route53, ACM, and KMS stay: they back the
# app module's ALB/ACM cert, which is expected to return soon.
# =============================================================================

data "aws_iam_policy_document" "deploy_security_permissions" {
  # Route 53
  statement {
    sid    = "Route53"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets", "route53:GetHostedZone",
      "route53:ListResourceRecordSets", "route53:GetChange",
      "route53:ListHostedZones"
    ]
    resources = ["*"]
  }

  # ACM
  statement {
    sid    = "ACM"
    effect = "Allow"
    actions = [
      "acm:RequestCertificate", "acm:DeleteCertificate",
      "acm:DescribeCertificate", "acm:ListCertificates",
      "acm:AddTagsToCertificate", "acm:ListTagsForCertificate"
    ]
    resources = ["*"]
  }

  # KMS
  statement {
    sid       = "KMS"
    effect    = "Allow"
    actions   = ["kms:Describe*", "kms:List*", "kms:GetKeyPolicy"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deploy_security_permissions" {
  name        = "${var.project}-github-actions-deploy-security"
  description = "Security operations permissions for terraform apply"
  policy      = data.aws_iam_policy_document.deploy_security_permissions.json

  tags = {
    Name = "${var.project}-github-actions-deploy-security"
  }
}

resource "aws_iam_role_policy_attachment" "deploy_state" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.terraform_state.arn
}

resource "aws_iam_role_policy_attachment" "deploy_permissions" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.deploy_permissions.arn
}

resource "aws_iam_role_policy_attachment" "deploy_security_permissions" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.deploy_security_permissions.arn
}

# =============================================================================
# Permissions Boundary: caps what the deploy role can ever do
# =============================================================================

# Permissions boundary = ceiling on what any role wearing it can do.
# Allow = the maximum service access. Deny = specific escalation paths blocked.
data "aws_iam_policy_document" "deploy_permissions_boundary" {

  # Ceiling: broad service-level access for project resources
  statement {
    sid    = "AllowProjectServices"
    effect = "Allow"
    actions = [
      "ec2:*",
      "ecs:*",
      "ecr:*",
      "rds:*",
      "s3:*",
      "iam:*",
      "lambda:*",
      "logs:*",
      "events:*",
      "sns:*",
      "elasticloadbalancing:*",
      "secretsmanager:*",
      "cloudtrail:*",
      "guardduty:*",
      "securityhub:*",
      "route53:*",
      "acm:*",
      "kms:*"
    ]
    resources = ["*"]
  }

  # Deny creating/modifying roles without this boundary attached
  statement {
    sid    = "DenyRoleCreationWithoutBoundary"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary"
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.permissions_boundary_arn]
    }
  }

  # Deny dangerous account-level actions that are never needed
  statement {
    sid    = "DenyAccountEscalation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateAccountPasswordPolicy",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "organizations:*",
      "account:*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deploy_permissions_boundary" {
  name        = "${var.project}-deploy-permissions-boundary"
  description = "Permissions boundary preventing privilege escalation from deploy role"
  policy      = data.aws_iam_policy_document.deploy_permissions_boundary.json

  tags = {
    Name = "${var.project}-deploy-permissions-boundary"
  }
}
