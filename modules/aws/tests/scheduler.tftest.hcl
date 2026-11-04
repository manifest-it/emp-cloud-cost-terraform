mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:root"
      user_id    = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      dns_suffix = "amazonaws.com"
      partition  = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json          = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
      minified_json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/emp-aws-cloud-cost-agent"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/emp-aws-cloud-cost-agent"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::emp-aws-cloud-cost-ag-123456789012-test"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:123456789012:emp-aws-cloud-cost-agent-scheduler-dlq"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:emp-aws-cloud-cost-agent"
    }
  }

  mock_resource "aws_scheduler_schedule" {
    defaults = {
      arn = "arn:aws:scheduler:us-east-1:123456789012:schedule/emp-aws-cloud-cost-agent/emp-aws-cloud-cost-agent-daily"
    }
  }

  mock_resource "aws_lambda_invocation" {
    defaults = {
      result = "null"
    }
  }
}

mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {
        sha256_base64 = base64sha256("test-artifact")
        version       = "0.3.0"
      }
    }
  }
}

variables {
  artifact_version      = "0.3.0"
  jfrog_artifactory_url = "https://example.jfrog.io/artifactory"
  jfrog_repository      = "cloud-cost-connectors"
  empirik_api_url       = "https://api.manifestit.tech/client/cost"
  org_key               = "test-org"
  mit_api_key           = "<API_KEY_PLACEHOLDER>"
  cost_source_id        = 42
}

run "daily_only_by_default" {
  command = plan

  assert {
    condition     = jsondecode(aws_scheduler_schedule.collector.target[0].input) == { mode = "daily" }
    error_message = "The daily schedule must send the daily payload."
  }

  assert {
    condition     = aws_scheduler_schedule.collector.schedule_expression == "cron(0 10 * * ? *)"
    error_message = "The daily schedule must keep its cron expression."
  }

  assert {
    condition     = length(aws_lambda_invocation.backfill) == 0
    error_message = "No backfill invocation may exist unless backfill_enabled is true."
  }

  assert {
    condition     = output.backfill_payload == null
    error_message = "backfill_payload must be null when backfill is disabled."
  }

  assert {
    condition     = length(aws_lambda_function_event_invoke_config.collector.destination_config[0].on_failure) == 1 && aws_lambda_function_event_invoke_config.collector.maximum_retry_attempts == 2
    error_message = "Failed asynchronous invocations must be routed to an on-failure destination after Lambda retries."
  }
}

run "backfill_by_days" {
  command = plan

  variables {
    backfill_enabled = true
  }

  assert {
    condition     = jsondecode(aws_lambda_invocation.backfill[0].input) == { mode = "backfill", days = 15 }
    error_message = "The backfill payload must default to 15 days."
  }

  assert {
    condition     = aws_lambda_invocation.backfill[0].function_name == aws_lambda_function.collector.function_name
    error_message = "The backfill must invoke the collector Lambda."
  }

  assert {
    condition     = aws_lambda_invocation.backfill[0].lifecycle_scope == "CREATE_ONLY" && aws_lambda_invocation.backfill[0].triggers == null
    error_message = "The backfill must run only on creation and have no triggers that replay it on unrelated changes."
  }

  assert {
    condition     = jsondecode(output.backfill_payload) == { mode = "backfill", days = 15 }
    error_message = "backfill_payload must expose the invocation payload."
  }

  assert {
    condition     = jsondecode(aws_scheduler_schedule.collector.target[0].input) == { mode = "daily" }
    error_message = "Enabling backfill must not change the daily payload."
  }
}

run "backfill_by_dates" {
  command = plan

  variables {
    backfill_enabled    = true
    backfill_start_date = "2026-04-01"
    backfill_end_date   = "2026-09-30"
  }

  assert {
    condition     = jsondecode(aws_lambda_invocation.backfill[0].input) == { mode = "backfill", start_date = "2026-04-01", end_date = "2026-09-30" }
    error_message = "Explicit dates must be sent instead of days."
  }
}

run "apply_backfill" {
  variables {
    backfill_enabled = true
    backfill_days    = 30
  }

  assert {
    condition     = length(aws_lambda_invocation.backfill) == 1
    error_message = "Applying with backfill_enabled must invoke the backfill."
  }
}

# Runs share state with apply_backfill. CREATE_ONLY re-invokes only when
# function_name, qualifier, triggers, or input change, so those must all match
# the applied invocation after unrelated changes.
run "unrelated_change_does_not_replay_backfill" {
  command = plan

  variables {
    backfill_enabled       = true
    backfill_days          = 30
    lambda_memory_mb       = 512
    lambda_timeout_seconds = 900
    schedule_expression    = "cron(0 6 * * ? *)"
  }

  assert {
    condition     = aws_lambda_invocation.backfill[0].input == run.apply_backfill.backfill_payload
    error_message = "Unrelated changes must not alter the backfill payload and re-run the backfill."
  }

  assert {
    condition     = aws_lambda_invocation.backfill[0].function_name == "emp-aws-cloud-cost-agent" && aws_lambda_invocation.backfill[0].qualifier == null && aws_lambda_invocation.backfill[0].triggers == null
    error_message = "Unrelated changes must not alter the invocation target or triggers and re-run the backfill."
  }
}

run "rejects_backfill_without_end" {
  command = plan

  variables {
    backfill_enabled    = true
    backfill_start_date = "2026-04-01"
  }

  expect_failures = [aws_lambda_invocation.backfill]
}

run "rejects_reversed_backfill_range" {
  command = plan

  variables {
    backfill_enabled    = true
    backfill_start_date = "2026-09-30"
    backfill_end_date   = "2026-04-01"
  }

  expect_failures = [aws_lambda_invocation.backfill]
}

run "rejects_invalid_backfill_date" {
  command = plan

  variables {
    backfill_start_date = "2026-02-30"
  }

  expect_failures = [var.backfill_start_date]
}

run "rejects_backfill_days_out_of_range" {
  command = plan

  variables {
    backfill_days = 401
  }

  expect_failures = [var.backfill_days]
}
