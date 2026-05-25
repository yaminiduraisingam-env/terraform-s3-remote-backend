variable "aws_region" {
  description = "AWS region for the workload bucket"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name used as a prefix for the bucket name"
  type        = string
  default     = "tf-remote-backend-demo"
}

variable "environment" {
  description = "Deployment environment — used in the bucket name"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}
