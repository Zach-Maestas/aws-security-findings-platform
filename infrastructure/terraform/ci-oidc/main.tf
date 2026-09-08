/*
==============================================================================
CI/CD OIDC Module: GitHub Actions Authentication
==============================================================================
Provisions OIDC federation for GitHub Actions CI/CD:
- OIDC identity provider for GitHub Actions
- Plan role: read-only, used on PR workflows for scans + terraform plan
- Deploy role: provisioning access with permissions boundary, used on merge to main

State is stored locally. Must be applied before the main infrastructure.
==============================================================================
*/

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  # sub claim includes immutable owner/repo IDs, not just names: repo:OWNER@ID/REPO@ID
  github_sub = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"

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

  tags = {
    Name = "${var.project}-oidc-provider"
  }
}

# =============================================================================
# Terraform State Access
# =============================================================================

data "aws_iam_policy_document" "terraform_state_read" {
  statement {
    sid       = "S3BucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.tfstate_bucket}"]
  }

  # Read state — both roles
  statement {
    sid       = "StateRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.tfstate_bucket}/${var.tfstate_key}"]
  }

  # Acquire and release the lock — both roles
  statement {
    sid    = "StateLock"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::${var.tfstate_bucket}/${var.tfstate_key}.tflock"]
  }
}

# Deploy role only — the one thing plan must never do
data "aws_iam_policy_document" "terraform_state_write" {
  statement {
    sid       = "StateWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.tfstate_bucket}/${var.tfstate_key}"]
  }
}

resource "aws_iam_policy" "terraform_state_read" {
  name        = "${var.project}-terraform-state-read"
  description = "Read Terraform remote state and acquire/release the S3 state lock"
  policy      = data.aws_iam_policy_document.terraform_state_read.json

  tags = {
    Name = "${var.project}-terraform-state-read"
  }
}

resource "aws_iam_policy" "terraform_state_write" {
  name        = "${var.project}-terraform-state-write"
  description = "Write Terraform remote state"
  policy      = data.aws_iam_policy_document.terraform_state_write.json

  tags = {
    Name = "${var.project}-terraform-state-write"
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
  policy_arn = aws_iam_policy.terraform_state_read.arn
}

resource "aws_iam_role_policy_attachment" "plan_permissions" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = aws_iam_policy.plan_permissions.arn
}

# =============================================================================
# Deploy Role: merge-to-main workflows or manual GitHub Actions trigger
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

data "aws_iam_policy_document" "deploy_permissions" {
  # Refresh/plan path. EC2 Describe* does not support resource-level
  # permissions in IAM, so "*" is required by AWS here, not by convenience.
  statement {
    sid       = "EC2Read"
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  statement {
    sid    = "NetworkWrite"
    effect = "Allow"
    actions = [
      # aws_vpc (incl. enable_dns_hostnames / enable_dns_support)
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",

      # aws_subnet (incl. map_public_ip_on_launch)
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",

      # aws_route_table + aws_route_table_association
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",

      # aws_route
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",

      # aws_internet_gateway
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",

      # aws_eip
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",

      # aws_nat_gateway
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",

      # Tagging on create and on update
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
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

resource "aws_iam_role_policy_attachment" "deploy_state" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.terraform_state_read.arn
}

resource "aws_iam_role_policy_attachment" "deploy_state_write" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.terraform_state_write.arn
}

resource "aws_iam_role_policy_attachment" "deploy_permissions" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.deploy_permissions.arn
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
