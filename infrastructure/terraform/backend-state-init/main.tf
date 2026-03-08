/*
==============================================================================
Backend State Init: Terraform Remote State Infrastructure
==============================================================================
Provisions bootstrap resources for Terraform remote state:
- S3 bucket for state storage with versioning and encryption
- DynamoDB table for state locking
- Public access blocks for security

Note: This module's state is stored locally. It exists as a separate bootstrap
workspace that must be applied before the main infrastructure. Remote state
isn't strictly required for a personal project, but demonstrates production
practices: state locking prevents concurrent modifications, versioning enables
rollback, and centralized storage supports team collaboration and CI/CD.
==============================================================================
*/

provider "aws" {
  region = "us-east-1"
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "tfstate" {
  bucket = "secops-pipeline-tfstate"

  tags = {
    Name = "secops-pipeline-tfstate"
  }
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "tflock" {
  name         = "terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "secops-pipeline-terraform-lock"
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "tfstate_versioning" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_sse" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "tfstate_block_access" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
