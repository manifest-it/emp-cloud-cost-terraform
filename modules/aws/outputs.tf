output "lambda_function_name" {
  description = "Name of the deployed AWS cost collector Lambda."
  value       = aws_lambda_function.collector.function_name
}

output "lambda_function_arn" {
  description = "ARN of the deployed AWS cost collector Lambda."
  value       = aws_lambda_function.collector.arn
}

output "connector_version" {
  description = "Exact immutable connector version deployed to the client account."
  value       = var.artifact_version
}

output "scheduler_name" {
  description = "Name of the daily EventBridge Scheduler schedule."
  value       = aws_scheduler_schedule.collector.name
}

output "runtime_role_arn" {
  description = "Least-privilege IAM role used by the collector."
  value       = aws_iam_role.collector.arn
}

output "artifact_bucket_name" {
  description = "Vendor-owned S3 bucket containing the versioned Lambda artifact."
  value       = aws_s3_bucket.artifacts.id
}

output "scheduler_dlq_url" {
  description = "Queue URL for scheduler invocations that exhaust retries."
  value       = aws_sqs_queue.scheduler_dlq.url
}

output "log_group_name" {
  description = "CloudWatch log group for collector executions."
  value       = aws_cloudwatch_log_group.collector.name
}