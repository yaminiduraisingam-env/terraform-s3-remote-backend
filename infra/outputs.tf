output "app_bucket_name" {
  description = "Name of the application S3 bucket"
  value       = aws_s3_bucket.app.bucket
}

output "app_bucket_arn" {
  description = "ARN of the application S3 bucket"
  value       = aws_s3_bucket.app.arn
}

output "app_bucket_region" {
  description = "AWS region where the application bucket was created"
  value       = var.aws_region
}

output "remote_state_location" {
  description = "S3 path where this workspace's state file is stored"
  value       = "s3://tf-remote-backend-state-${data.aws_caller_identity.current.account_id}-${var.aws_region}/infra/terraform.tfstate"
}
