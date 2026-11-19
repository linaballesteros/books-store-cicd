data "aws_caller_identity" "current" {}

locals {
  alb_log_bucket     = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-alb-logs"
  alb_log_bucket_arn = "arn:aws:s3:::${local.alb_log_bucket}"
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = local.alb_log_bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = local.alb_log_bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = local.alb_log_bucket
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowLoadBalancerLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${local.alb_log_bucket_arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid       = "RequireSecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.alb_log_bucket_arn, "${local.alb_log_bucket_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } }
      },
    ]
  })
}
