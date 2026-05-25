variable "aws_region" {
  description = "AWS region where the state bucket and lock table will be created"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
  default     = "tf-remote-backend"
}
