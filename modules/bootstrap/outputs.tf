output "state_bucket_name" {
  description = "Name of the S3 bucket that stores OpenTofu state"
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket"
  value       = aws_s3_bucket.state.arn
}

output "state_bucket_region" {
  description = "Region the state bucket was created in"
  value       = aws_s3_bucket.state.region
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for state locking"
  value       = aws_dynamodb_table.lock.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB lock table"
  value       = aws_dynamodb_table.lock.arn
}

output "aws_account_id" {
  description = "AWS account ID the resources were deployed into"
  value       = data.aws_caller_identity.current.account_id
}
