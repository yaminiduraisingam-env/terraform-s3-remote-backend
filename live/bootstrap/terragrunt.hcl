# =============================================================================
# live/bootstrap/terragrunt.hcl
#
# Bootstrap is the ONE exception to the root remote_state config.
# It cannot use the S3 backend because it is responsible for CREATING
# that bucket. env0 manages bootstrap state internally.
#
# This environment is deployed ONCE. After it succeeds, all other
# environments inherit the root remote_state config and use the S3
# backend that bootstrap created.
# =============================================================================

# Do NOT include the root terragrunt.hcl here — bootstrap manages its
# own state and does not use the S3 remote backend.

terraform {
  source = "../../modules/bootstrap"
}

# Override the provider generation directly (no root include)
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "OpenTofu"
      Project     = "tf-remote-backend"
      Environment = "bootstrap"
    }
  }
}
EOF
}

inputs = {
  aws_region   = "eu-central-1"
  project_name = "tf-remote-backend"
}
