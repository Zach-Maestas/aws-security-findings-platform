/*
==============================================================================
Security Ops Module: Detection and Response Infrastructure
==============================================================================
Provisions security operations components:
- CloudTrail for API audit logging (S3 delivery)
- GuardDuty and Security Hub for threat detection 
- EventBridge and Lambda for automated incident response
==============================================================================
*/

# CloudTrail Initialization
resource "aws_cloudtrail" "this" {
  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]

  name                          = "${var.project}-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cw_cloudtrail_logs_group.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch_role.arn

  tags = {
    Name = "${var.project}-cloudtrail"
  }
}

# S3 Bucket for CloudTrail log delivery
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "${var.project}-cloudtrail-logs"
  force_destroy = true

  tags = {
    Name = "${var.project}-cloudtrail-logs"
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true  # Prevents new ACLs that grant public access from being created
  block_public_policy     = true  # Prevents new bucket policies that grant public access from being PUT
  ignore_public_acls      = true  # Makes S3 ignore public ACLs
  restrict_public_buckets = true  # Restricts access to the bucket so that only AWS services and authorized users within this account can access it
}

# S3 bucket policy granting CloudTrail permission to deliver logs
data "aws_iam_policy_document" "cloudtrail_s3_access" {
  statement {
    sid    = "AWSCloudTrailACLCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-cloudtrail"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-cloudtrail"]
    }
  }
}

# S3 Bucket Policy attachment for CloudTrail Logs
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_s3_access.json
}

# CloudWatch Log Group to ingest CloudTrail logs for real-time events
resource "aws_cloudwatch_log_group" "cw_cloudtrail_logs_group" {
  name              = "/cloudtrail/${var.project}-cloudtrail"
  retention_in_days = 7

  tags = {
    Name = "${var.project}-cloudtrail-logs"
  }
}

# IAM Role that allows CloudTrail to write CloudWatch Logs
resource "aws_iam_role" "cloudtrail_cloudwatch_role" {
  name = "${var.project}-cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name = "${var.project}-cloudtrail-cloudwatch-role"
  }
}

# IAM Policy document to allow CloudTrail to upload logs to CloudWatch
data "aws_iam_policy_document" "cloudtrail_cloudwatch_logs" {
  statement {
    sid    = "CloudWatchLogIngestionFromCloudTrail"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "${aws_cloudwatch_log_group.cw_cloudtrail_logs_group.arn}:*"
    ]
  }
}

# IAM Policy that allows CloudTrail to delivery logs to CloudWatch
resource "aws_iam_policy" "cloudtrail_cloudwatch_logs_policy" {
  name        = "${var.project}-cloudtrail-cloudwatch-policy"
  description = "Policy to allow CloudTrail to deliver logs to CloudWatch"
  policy      = data.aws_iam_policy_document.cloudtrail_cloudwatch_logs.json

  tags = {
    Name = "${var.project}-cloudtrail-cloudwatch-policy"
  }
}

# IAM Policy attachment for CloudTrail -> CloudWatch
resource "aws_iam_role_policy_attachment" "cloudtrail_cloudwatch_logs_policy_attach" {
  role       = aws_iam_role.cloudtrail_cloudwatch_role.name
  policy_arn = aws_iam_policy.cloudtrail_cloudwatch_logs_policy.arn
}

# AWS GuardDuty
resource "aws_guardduty_detector" "guardduty" {
  enable = true

  tags = {
    Name = "${var.project}-guardduty"
  }
}

# Enable AWS GuardDuty S3 Detection
resource "aws_guardduty_detector_feature" "s3_protection" {
  detector_id = aws_guardduty_detector.guardduty.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

# AWS Security Hub
resource "aws_securityhub_account" "security_hub" {}

# --- INCIDENT RESPONSE ---

# CloudWatch Event rule that captures AttachRolePolicy with AdministratorAccess
resource "aws_cloudwatch_event_rule" "iam_admin_attachment" {
  name        = "${var.project}-capture-iam-admin-attachment"
  description = "Capture AttachRolePolicy with AdministratorAccess"

  tags = {
    Name = "${var.project}-capture-iam-admin-attachment"
  }

  event_pattern = jsonencode({
    source      = ["aws.iam"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["AttachRolePolicy"]
      requestParameters = {
        policyArn = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      }
    }
  })
}

# CloudWatch Event rule that captures AuthorizeSecurityGroupIngress calls
resource "aws_cloudwatch_event_rule" "sg_ingress_revoke" {
  name        = "${var.project}-capture-sg-ingress"
  description = "Captures security group ingress changes for dangerous port/CIDR remediation"

  tags = {
    Name = "${var.project}-capture-sg-ingress"
  }

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["AuthorizeSecurityGroupIngress"]
    }
  })
}

# Set Lambda as CloudWatch Event target (IAM Admin Revoke)
resource "aws_cloudwatch_event_target" "iam_admin_revoke_lambda" {
  rule      = aws_cloudwatch_event_rule.iam_admin_attachment.name
  target_id = "iam-admin-revoke-lambda"
  arn       = aws_lambda_function.iam_admin_policy_revoke.arn
}

# Set Lambda as CloudWatch Event target (SG Ingress Revoke)
resource "aws_cloudwatch_event_target" "sg_ingress_revoke_lambda" {
  rule      = aws_cloudwatch_event_rule.sg_ingress_revoke.name
  target_id = "sg-ingress-revoke-lambda"
  arn       = aws_lambda_function.sg_ingress_revoke.arn
}

# Lambda execution role
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name = "${var.project}-lambda-exec-role"
  }
}

# IAM Policy to allow Lambda remediation actions (IAM, EC2, CloudWatch Logs)
data "aws_iam_policy_document" "lambda_remediation_permissions" {
  statement {
    sid    = "AllowIAMRemediation"
    effect = "Allow"
    actions = [
      "iam:DetachRolePolicy"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
    ]
  }
  statement {
    sid       = "AllowSGDescribe"
    effect    = "Allow"
    actions   = ["ec2:DescribeSecurityGroups"]
    resources = ["*"]
  }
  statement {
    sid     = "AllowSGRemediation"
    effect  = "Allow"
    actions = ["ec2:RevokeSecurityGroupIngress"]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:security-group/*"
    ]
  }
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project}-*:*"
    ]
  }
  statement {
    sid       = "AllowPublishToOneTopic"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.sns_security_alerts.arn]
  }
}

# Policy to allow Lambda to perform remediation actions and push logs
resource "aws_iam_policy" "lambda_remediation_permissions" {
  name        = "${var.project}-lambda-remediation"
  description = "Policy to allow Lambda to perform remediation actions and push logs to CloudWatch"
  policy      = data.aws_iam_policy_document.lambda_remediation_permissions.json

  tags = {
    Name = "${var.project}-lambda-remediation"
  }
}

# Policy Attachment for Lambda exec role
resource "aws_iam_role_policy_attachment" "lambda_remediation_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_remediation_permissions.arn
}

# Package Python code for 'iam_admin_revoke.py'
data "archive_file" "iam_admin_policy_revoke" {
  type        = "zip"
  source_file = "${path.root}/../scripts/aws-lambda/iam_admin_revoke.py"
  output_path = "${path.root}/../scripts/aws-lambda/iam_admin_revoke.zip"
}

# Package Python code for 'sg_ingress_revoke.py'
data "archive_file" "sg_ingress_revoke" {
  type        = "zip"
  source_file = "${path.root}/../scripts/aws-lambda/sg_ingress_revoke.py"
  output_path = "${path.root}/../scripts/aws-lambda/sg_ingress_revoke.zip"
}

# Lambda function to revoke AdministratorAccess from an IAM role
resource "aws_lambda_function" "iam_admin_policy_revoke" {
  filename         = data.archive_file.iam_admin_policy_revoke.output_path
  function_name    = "${var.project}-iam-admin-policy-revoke"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "iam_admin_revoke.handler"
  runtime          = "python3.13"
  source_code_hash = data.archive_file.iam_admin_policy_revoke.output_base64sha256

  tags = {
    Name = "${var.project}-iam-admin-policy-revoke"
  }

  environment {
    variables = {
      LOG_LEVEL     = "info"
      SNS_TOPIC_ARN = aws_sns_topic.sns_security_alerts.arn
    }
  }
}

# Lambda function to revoke dangerous SG ingress rules
resource "aws_lambda_function" "sg_ingress_revoke" {
  filename         = data.archive_file.sg_ingress_revoke.output_path
  function_name    = "${var.project}-sg-ingress-revoke"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "sg_ingress_revoke.handler"
  runtime          = "python3.13"
  source_code_hash = data.archive_file.sg_ingress_revoke.output_base64sha256

  tags = {
    Name = "${var.project}-sg-ingress-revoke"
  }

  environment {
    variables = {
      LOG_LEVEL     = "info"
      SNS_TOPIC_ARN = aws_sns_topic.sns_security_alerts.arn
    }
  }
}

# Give permission to EventBridge to invoke the Lambda IAM Admin revoke remediation function
resource "aws_lambda_permission" "eventbridge_invoke_iam_revoke" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iam_admin_policy_revoke.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.iam_admin_attachment.arn
}

# Give permission to EventBridge to invoke the SG ingress revoke Lambda
resource "aws_lambda_permission" "eventbridge_invoke_sg_ingress_revoke" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sg_ingress_revoke.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sg_ingress_revoke.arn
}

# SNS topic for security alert notifications
resource "aws_sns_topic" "sns_security_alerts" {
  name = "${var.project}-security-alerts"

  tags = {
    Name = "${var.project}-security-alerts"
  }
}

# SMS subscription for security alerts
resource "aws_sns_topic_subscription" "sns_security_alerts_subscription" {
  topic_arn = aws_sns_topic.sns_security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}