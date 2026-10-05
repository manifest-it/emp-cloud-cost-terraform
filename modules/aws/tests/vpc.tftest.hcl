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

run "non_vpc_by_default" {
  command = plan

  assert {
    condition     = aws_lambda_function.collector.function_name == "emp-aws-cloud-cost-agent"
    error_message = "Lambda must use the fixed Empirik AWS cloud cost agent name."
  }

  assert {
    condition     = aws_lambda_function.collector.description == "Empirik AWS cloud cost collector 0.3.0"
    error_message = "Lambda description must include Empirik branding and the artifact version."
  }

  assert {
    condition     = length(aws_lambda_function.collector.vpc_config) == 0
    error_message = "Lambda must remain outside a VPC when no VPC inputs are supplied."
  }

  assert {
    condition     = aws_lambda_function.collector.environment[0].variables.BACKFILL_LAST_15_DAYS == "false"
    error_message = "Last-15-day backfill must be disabled by default."
  }

  assert {
    condition     = nonsensitive(aws_lambda_function.collector.environment[0].variables.MIT_API_KEY) == "<API_KEY_PLACEHOLDER>"
    error_message = "Lambda must receive the supplied MIT API key."
  }

  assert {
    condition     = aws_lambda_function.collector.environment[0].variables.COST_SOURCE_ID == "42"
    error_message = "Lambda must receive the supplied Cost Source Configuration ID."
  }

  assert {
    condition     = !contains(nonsensitive(keys(aws_lambda_function.collector.environment[0].variables)), "X_API_KEY")
    error_message = "Lambda must not receive the retired X_API_KEY variable."
  }
}

run "enables_last_15_day_backfill" {
  command = plan

  variables {
    backfill_last_15_days = true
  }

  assert {
    condition     = aws_lambda_function.collector.environment[0].variables.BACKFILL_LAST_15_DAYS == "true"
    error_message = "Lambda must receive the enabled last-15-day backfill setting."
  }
}

run "rejects_retired_ingestion_path" {
  command = plan

  variables {
    empirik_api_url = "https://api.manifestit.tech/api/v1/cloud-cost"
  }

  expect_failures = [var.empirik_api_url]
}

run "rejects_obsolete_versioned_ingestion_path" {
  command = plan

  variables {
    empirik_api_url = "https://api.manifestit.tech/api/v1/client/cost"
  }

  expect_failures = [var.empirik_api_url]
}

run "rejects_empty_mit_api_key" {
  command = plan

  variables {
    mit_api_key = ""
  }

  expect_failures = [var.mit_api_key]
}

run "uses_existing_vpc" {
  command = plan

  variables {
    vpc_subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    vpc_security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = toset(one(aws_lambda_function.collector.vpc_config).subnet_ids) == toset(var.vpc_subnet_ids)
    error_message = "Lambda must use the supplied existing subnets."
  }

  assert {
    condition     = toset(one(aws_lambda_function.collector.vpc_config).security_group_ids) == toset(var.vpc_security_group_ids)
    error_message = "Lambda must use the supplied existing security groups."
  }
}

run "rejects_partial_vpc_configuration" {
  command = plan

  variables {
    vpc_subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [aws_lambda_function.collector]
}
