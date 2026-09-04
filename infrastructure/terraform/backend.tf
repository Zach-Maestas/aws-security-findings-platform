terraform {
  backend "s3" {
    bucket       = "aws-security-findings-platform-tfstate"
    key          = "platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}