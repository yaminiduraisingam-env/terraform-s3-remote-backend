# =============================================================================
# ROOT terragrunt.hcl
#
# This file is the single source of truth for the remote backend config.
# Every environment under live/ inherits this automatically via
# include "root" { path = find_in_parent_folders() }
#
# Terragrunt generates backend.tf and provider.tf in each module directory
# at runtime — you never need to write these files manually.
# =============================================================================

# -----------------------------------------------------------------------------
# REMOTE STATE — defined once, inherited by all child modules
# -----------------------------------------------------------------------------
remote_state {
  backend = "s3"

  # Terragrunt generates a backend.tf file in each module directory at runtime
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "tf-remote-backend-state-${get_aws_account_id()}-eu-central-1"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tf-remote-backend-locks"
    encrypt        = true
  }
}

# -----------------------------------------------------------------------------
# AWS PROVIDER — generated in every child module at runtime
# -----------------------------------------------------------------------------
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
      ManagedBy = "OpenTofu"
      Project   = "tf-remote-backend"
    }
  }
}
EOF
}

# -----------------------------------------------------------------------------
# COMMON INPUTS — available to all child modules
# -----------------------------------------------------------------------------
inputs = {
  aws_region = "eu-central-1"
}
