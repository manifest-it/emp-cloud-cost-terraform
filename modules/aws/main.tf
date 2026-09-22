data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  resource_name   = var.name_prefix
  lambda_zip_path = "${path.module}/artifacts/bootstrap-${var.artifact_version}.zip"
  artifact_key    = "releases/${var.artifact_version}/bootstrap.zip"
}

data "external" "collector_artifact" {
  program = [
    "${path.module}/scripts/download-jfrog-artifact.sh",
    var.jfrog_artifactory_url,
    var.jfrog_repository,
    var.artifact_version,
    local.lambda_zip_path,
  ]
}

resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${substr(local.resource_name, 0, 20)}-${data.aws_caller_identity.current.account_id}-"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "artifact_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    actions = [
      "s3:*",
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifact_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

resource "aws_s3_object" "collector" {
  bucket = aws_s3_bucket.artifacts.id
  key    = local.artifact_key
  source = local.lambda_zip_path

  source_hash            = data.external.collector_artifact.result.sha256_base64
  server_side_encryption = "AES256"

  depends_on = [
    aws_s3_bucket_ownership_controls.artifacts,
    aws_s3_bucket_public_access_block.artifacts,
    aws_s3_bucket_server_side_encryption_configuration.artifacts,
    aws_s3_bucket_versioning.artifacts,
  ]

  lifecycle {
    precondition {
      condition     = data.external.collector_artifact.result.version == var.artifact_version
      error_message = "The downloaded JFrog artifact version does not match artifact_version."
    }
  }
}

resource "aws_cloudwatch_log_group" "collector" {
  name              = "/aws/lambda/${local.resource_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "collector" {
  function_name = local.resource_name
  description   = "AWS cloud cost collector ${var.artifact_version}"
  role          = aws_iam_role.collector.arn

  s3_bucket         = aws_s3_object.collector.bucket
  s3_key            = aws_s3_object.collector.key
  s3_object_version = aws_s3_object.collector.version_id
  source_code_hash  = data.external.collector_artifact.result.sha256_base64

  architectures = ["arm64"]
  runtime       = "provided.al2023"
  handler       = "bootstrap"
  memory_size   = var.lambda_memory_mb
  timeout       = var.lambda_timeout_seconds

  reserved_concurrent_executions = 1
  tags                           = var.tags

  environment {
    variables = {
      MANAGEMENT_ACCOUNT_ID  = data.aws_caller_identity.current.account_id
      CONNECTOR_VERSION      = var.artifact_version
      COST_EXPLORER_REGION   = "us-east-1"
      EMPIRIK_API_URL        = var.empirik_api_url
      ORG_KEY                = var.org_key
      X_API_KEY              = var.x_api_key
      TIMEZONE               = var.timezone
      EVALUATION_LAG_DAYS    = tostring(var.evaluation_lag_days)
      ANOMALY_THRESHOLD_PCT  = tostring(var.anomaly_threshold_pct)
      MIN_ABSOLUTE_DELTA_USD = tostring(var.min_absolute_delta_usd)
      MIN_BASELINE_USD       = tostring(var.min_baseline_usd)
      ACCOUNT_ALLOWLIST      = join(",", var.account_allowlist)
      ACCOUNT_DENYLIST       = join(",", var.account_denylist)
    }
  }

  depends_on = [aws_cloudwatch_log_group.collector]

  lifecycle {
    precondition {
      condition     = var.expected_management_account_id == null || data.aws_caller_identity.current.account_id == var.expected_management_account_id
      error_message = "The active AWS account does not match expected_management_account_id."
    }
  }
}

resource "aws_sqs_queue" "scheduler_dlq" {
  name                      = "${local.resource_name}-scheduler-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_scheduler_schedule_group" "collector" {
  name = local.resource_name
  tags = var.tags
}

resource "aws_scheduler_schedule" "collector" {
  name                         = "${local.resource_name}-daily"
  group_name                   = aws_scheduler_schedule_group.collector.name
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.collector.arn
    role_arn = aws_iam_role.scheduler.arn

    dead_letter_config {
      arn = aws_sqs_queue.scheduler_dlq.arn
    }

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }
}

resource "aws_lambda_permission" "scheduler" {
  statement_id  = "AllowEventBridgeSchedulerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.collector.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.collector.arn
}
