###############################################################################
# DATA SOURCES
###############################################################################

data "aws_caller_identity" "current" {}

###############################################################################
# LOCALS
###############################################################################

locals {
  # Unique bucket name: <project>-state-<account_id>-<region>
  # Account ID ensures global uniqueness. Region keeps it human-readable.
  bucket_name = "${var.project_name}-state-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  table_name  = "${var.project_name}-locks"
}

###############################################################################
# S3 BUCKET — Terraform remote state storage
###############################################################################

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.bucket_name

  # Safety net: Terraform will refuse to destroy this bucket even on `terraform destroy`.
  # Remove this block manually if you ever want to decommission the backend.
  #lifecycle {
    #prevent_destroy = true
  #}
}

# Enable versioning so every state push creates a recoverable version.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# AES-256 server-side encryption — no extra cost, no KMS key needed.
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block ALL public access — state files must never be public.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cost optimisation: expire non-current (old) state versions after 90 days.
# This keeps your last 90 days of history without accumulating storage costs.
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  # Versioning must be enabled before a lifecycle rule can act on versions.
  depends_on = [aws_s3_bucket_versioning.terraform_state]

  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    # Only apply to objects that look like Terraform state files.
    filter {
      prefix = var.state_key_prefix
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Clean up any failed multi-part uploads after 7 days.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

###############################################################################
# DYNAMODB TABLE — Terraform state locking
###############################################################################

# PAY_PER_REQUEST billing: you only pay per read/write.
# State lock operations are extremely infrequent — effectively free under
# normal usage and well within the DynamoDB free tier (25 WCU + 25 RCU/month).
resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"

  # "LockID" is the required hash key that Terraform's S3 backend uses.
  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # PITR disabled — the state bucket itself provides recovery; no need for
  # table-level point-in-time recovery (which adds ~$0.20/GB/month).
  point_in_time_recovery {
    enabled = false
  }

  # TTL not needed — lock items are short-lived and deleted by Terraform itself.
}
