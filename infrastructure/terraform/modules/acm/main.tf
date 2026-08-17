/*
==============================================================================
ACM Module: TLS Certificate Management
==============================================================================
Provisions and validates an AWS Certificate Manager (ACM) certificate:
- Creates ACM certificate for the API domain
- Automatically creates DNS validation records in Route 53
- Waits for certificate validation to complete
- Used by ALB for HTTPS termination
==============================================================================
*/

# ACM Certificate
resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project}-acm-cert"
  }
}

# Create Route 53 validation records
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 604
}

# Validate the ACM certificate
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

