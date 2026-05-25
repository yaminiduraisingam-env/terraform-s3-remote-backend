# =============================================================================
# modules/app-bucket/main.tf
#
# Creates a demo workload S3 bucket — the "proof" resource that shows
# env0 + OpenTofu + Terragrunt working end to end.
#
# Its state is stored remotely in the S3 bucket created by bootstrap,
# and each deploy acquires/releases a lock via the DynamoDB table.
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "${var.project_name}-${var.environment}-${local.account_id}"
}

# The demo workload bucket
resource "aws_s3_bucket" "app" {
  bucket = local.bucket_name
}

# AES-256 encryption at rest — free, no KMS key required
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning suspended — not needed for the demo workload bucket
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Suspended"
  }
}
