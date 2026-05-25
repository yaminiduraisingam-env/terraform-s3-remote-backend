# live/bootstrap/terragrunt.hcl

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket  = "tf-bootstrap-state-013141018419"
    key     = "bootstrap/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}
EOF
}

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

terraform {
  source = "../../modules/bootstrap"
}

inputs = {
  aws_region   = "eu-central-1"
  project_name = "tf-remote-backend"
}
