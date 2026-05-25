# =============================================================================
# modules/bootstrap/main.tf
#
# Creates the remote backend infrastructure:
#   1. S3 bucket       — stores OpenTofu state files
#   2. DynamoDB table  — stores state locks
#
# This module is deployed ONCE and never touched again in normal operation.
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "${var.project_name}-state-${local.account_id}-${var.aws_region}"
  table_name  = "${var.project_name}-locks"
}

# -----------------------------------------------------------------------------
# S3 BUCKET — Remote State Storage
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket        = local.bucket_name
  force_destroy = true # Allows clean teardown via env0 Destroy

  lifecycle {
    prevent_destroy = false
  }
}

# Versioning — every state change creates a new version, enabling rollback
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption at rest — free using AWS-managed keys (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access — state files must never be public
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule — expire old non-current state versions after 90 days
# Keeps storage costs at zero while retaining recent history
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  depends_on = [aws_s3_bucket_versioning.state]

  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 5
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# -----------------------------------------------------------------------------
# DYNAMODB TABLE — State Locking
#
# PAY_PER_REQUEST billing: no minimum cost, charged only for actual
# lock operations (~2 per deploy). Effectively free at this usage level.
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "lock" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
