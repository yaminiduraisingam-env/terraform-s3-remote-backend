###############################################################################
# REMOTE BACKEND
#
# This block is intentionally empty — all values are supplied at `init` time
# via the backend.hcl file (partial configuration pattern).
#
# Local usage:
#   terraform init -backend-config=backend.hcl
#
# env0:
#   Set the "Terraform Init Arguments" field in the env0 environment to:
#   -backend-config=backend.hcl
#   (or supply individual TF_BACKEND_* env vars — see README)
###############################################################################

terraform {
  backend "s3" {
  }
}
