# =============================================================================
# live/dev/app-bucket/terragrunt.hcl
#
# Inherits the root remote_state config — Terragrunt automatically generates:
#
#   backend.tf with:
#     bucket         = "tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1"
#     key            = "live/dev/app-bucket/terraform.tfstate"
#     region         = "eu-central-1"
#     dynamodb_table = "tf-remote-backend-locks"
#     encrypt        = true
#
# No manual backend configuration needed.
# =============================================================================

# Inherit everything from the root terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/app-bucket"
}

inputs = {
  aws_region   = "eu-central-1"
  project_name = "tf-remote-backend-demo"
  environment  = "dev"
}
