/*
==============================================================================
Bootstrap: Terraform Remote State Infrastructure
==============================================================================
Provisions bootstrap resources for Terraform remote state:
- S3 bucket for state storage with versioning and encryption

State is stored locally. Must be applied before the main infrastructure.

==============================================================================
*/

provider "aws" {
  region = "us-east-1"
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "tfstate" {
  bucket        = "${var.project}-tfstate"
  force_destroy = true # required for a clean replace/destroy since versioning keeps old object versions

  tags = {
    Name = "${var.project}-tfstate"
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
