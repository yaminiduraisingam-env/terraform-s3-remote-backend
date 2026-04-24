###############################################################################
# backend.hcl — Terraform S3 Remote Backend Configuration
#
# HOW TO USE:
#   1. Run the bootstrap workspace first.
#   2. Replace <ACCOUNT_ID> below with the value from the bootstrap output
#      "aws_account_id" (or "state_bucket_name").
#   3. Run: terraform init -backend-config=backend.hcl
#
# The full bucket name follows this pattern:
#   tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1
#
# TIP: Copy the "backend_hcl_snippet" output from the bootstrap workspace —
# it already has all the correct values filled in.
###############################################################################

bucket         = "tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1"
key            = "infra/terraform.tfstate"
region         = "eu-central-1"
dynamodb_table = "tf-remote-backend-locks"
encrypt        = true
