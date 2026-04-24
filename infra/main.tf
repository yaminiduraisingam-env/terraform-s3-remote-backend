###############################################################################
# DATA SOURCES
###############################################################################

data "aws_caller_identity" "current" {}

###############################################################################
# LOCALS
###############################################################################

locals {
  # Bucket names must be globally unique — appending account ID ensures that.
  app_bucket_name = "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

###############################################################################
# APPLICATION S3 BUCKET
#
# This is the "proof" resource: it is created by the infra workspace whose
# state is stored remotely in the S3 bucket + DynamoDB table created by the
# bootstrap workspace.
###############################################################################

resource "aws_s3_bucket" "app" {
  bucket = local.app_bucket_name

  tag = {
      "name" = "test-tag-env0"
  }
}

# Suspend versioning on the app bucket — we don't need object history here
# and it keeps storage costs at zero inside the free tier.
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Suspended"
  }
}

# AES-256 encryption — free, no KMS key required.
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access — good baseline for any bucket.
resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
