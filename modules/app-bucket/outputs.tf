output "app_bucket_name" {
  description = "Name of the demo workload S3 bucket"
  value       = aws_s3_bucket.app.id
}

output "app_bucket_arn" {
  description = "ARN of the demo workload S3 bucket"
  value       = aws_s3_bucket.app.arn
}

output "app_bucket_region" {
  description = "Region the demo bucket was created in"
  value       = aws_s3_bucket.app.region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}
