variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "Must be a valid AWS region name (e.g. eu-central-1)."
  }
}

variable "project_name" {
  description = "Project name — used as a prefix for all resource names"
  type        = string
  default     = "tf-remote-backend"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name must be 3-24 lowercase alphanumeric characters or hyphens."
  }
}

variable "state_key_prefix" {
  description = "Optional prefix added inside the S3 bucket for all state files"
  type        = string
  default     = ""
}

variable "state_bucket_name" {
  type = string
}
