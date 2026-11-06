mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email = "mock-service-account@customer-connector-project.iam.gserviceaccount.com"
    }
  }

  mock_resource "google_secret_manager_secret_version" {
    defaults = {
      version = "1"
    }
  }
}

variables {
  deployment_project_id     = "customer-connector-project"
  billing_export_project_id = "customer-billing-export"
  bigquery_query_project_id = "customer-query-project"
  bigquery_dataset          = "billing_export"
  bigquery_table            = "gcp_billing_export_v1_ABCDEF_ABCDEF_ABCDEF"
  billing_account_id        = "ABCDEF-ABCDEF-ABCDEF"
  artifact_version          = "2.0.0"
  jfrog_artifactory_url     = "https://example.jfrog.io/artifactory"
  jfrog_repository          = "cloud-cost-connectors"
  empirik_api_url           = "https://api.manifestit.tech/client/cost"
  org_key                   = "test-org"
  cost_source_id            = 42
  mit_api_key               = "<API_KEY_PLACEHOLDER>"
  environment_name          = "production"
  manage_project_services   = false
}

run "plans_least_privilege_connector" {
  command = plan

  assert {
    condition     = length(google_bigquery_dataset.billing_export) == 1 && google_bigquery_dataset.billing_export[0].location == "US"
    error_message = "The connector must create a US multi-region billing export dataset by default."
  }

  assert {
    condition     = google_artifact_registry_repository.collector.docker_config[0].immutable_tags
    error_message = "Artifact Registry must reject overwritten collector tags."
  }

  assert {
    condition     = google_bigquery_dataset_iam_member.billing_reader.role == "roles/bigquery.dataViewer"
    error_message = "The runtime must receive BigQuery dataViewer only at dataset scope."
  }

  assert {
    condition     = google_project_iam_member.query_job_user.role == "roles/bigquery.jobUser"
    error_message = "The runtime must receive only BigQuery jobUser at query-project scope."
  }

  assert {
    condition     = google_service_account.runtime.account_id != google_service_account.scheduler.account_id
    error_message = "Runtime and scheduler must use separate service accounts."
  }

  assert {
    condition     = google_cloud_run_v2_job.collector.template[0].task_count == 1 && google_cloud_run_v2_job.collector.template[0].parallelism == 1
    error_message = "The collector must run as one non-parallel Cloud Run task."
  }

  assert {
    condition     = one([for env in google_cloud_run_v2_job.collector.template[0].template[0].containers[0].env : env if env.name == "COST_SOURCE_ID"]).value == "42"
    error_message = "COST_SOURCE_ID must be passed to the collector."
  }

  assert {
    condition     = one([for env in google_cloud_run_v2_job.collector.template[0].template[0].containers[0].env : env if env.name == "MIT_API_KEY"]).value_source[0].secret_key_ref[0].secret == google_secret_manager_secret.mit_api_key.secret_id
    error_message = "MIT_API_KEY must be injected from Secret Manager."
  }

  assert {
    condition     = one([for env in google_cloud_run_v2_job.collector.template[0].template[0].containers[0].env : env if env.name == "BIGQUERY_TABLE"]).value == var.bigquery_table
    error_message = "Cloud Run must receive the configured billing export table."
  }

  assert {
    condition     = google_cloud_scheduler_job.collector.http_target[0].uri == "https://run.googleapis.com/v2/projects/customer-connector-project/locations/us-central1/jobs/emp-cloud-cost-collector:run"
    error_message = "Cloud Scheduler must call the Cloud Run Jobs run API directly."
  }

  assert {
    condition     = google_cloud_run_v2_job_iam_member.scheduler_invoker.role == "roles/run.invoker"
    error_message = "The scheduler must receive only the Cloud Run invoker role on the job."
  }
}

run "backfill_disabled_by_default" {
  command = plan

  assert {
    condition     = length(terraform_data.backfill) == 0
    error_message = "No backfill execution may exist unless backfill_enabled is true."
  }

  assert {
    condition     = output.backfill_args == null
    error_message = "backfill_args must be null when backfill is disabled."
  }

  assert {
    condition     = alltrue([for env in google_cloud_run_v2_job.collector.template[0].template[0].containers[0].env : !startswith(env.name, "BACKFILL_")])
    error_message = "Backfill must not be configured through the job environment."
  }
}

run "backfill_default_range" {
  command = plan

  variables {
    backfill_enabled = true
  }

  assert {
    condition     = terraform_data.backfill[0].input == "--mode=backfill"
    error_message = "Without dates, the backfill must let the collector choose its default range at execution."
  }

  assert {
    condition     = terraform_data.backfill[0].triggers_replace == { start_date = "", end_date = "" }
    error_message = "Only the backfill dates may replace the backfill and run it again."
  }

  assert {
    condition     = output.backfill_args == "--mode=backfill"
    error_message = "backfill_args must expose the execution arguments."
  }

  assert {
    condition     = alltrue([for env in google_cloud_run_v2_job.collector.template[0].template[0].containers[0].env : !startswith(env.name, "BACKFILL_")]) && google_cloud_run_v2_job.collector.template[0].template[0].containers[0].args == null
    error_message = "Enabling backfill must not change the saved job configuration."
  }

  assert {
    condition     = google_cloud_scheduler_job.collector.http_target[0].body == base64encode("{}")
    error_message = "The daily schedule must keep running the job without arguments."
  }
}

run "backfill_explicit_range" {
  command = plan

  variables {
    backfill_enabled    = true
    backfill_start_date = "2026-04-01"
    backfill_end_date   = "2026-09-30"
  }

  assert {
    condition     = terraform_data.backfill[0].input == "--mode=backfill,--start-date=2026-04-01,--end-date=2026-09-30"
    error_message = "Explicit dates must be passed as execution arguments."
  }

  assert {
    condition     = terraform_data.backfill[0].triggers_replace == { start_date = "2026-04-01", end_date = "2026-09-30" }
    error_message = "Changing the backfill dates must replace the backfill and run it again."
  }
}

# Plan-only: terraform test runs provisioners on apply, even for overridden
# resources. Replacement depends only on triggers_replace, so equal triggers and
# input after unrelated changes mean the backfill is not replayed.
run "unrelated_change_does_not_replay_backfill" {
  command = plan

  variables {
    backfill_enabled         = true
    backfill_start_date      = "2026-04-01"
    backfill_end_date        = "2026-09-30"
    artifact_version         = "2.1.0"
    backfill_timeout_seconds = 7200
    backfill_wait            = false
    timeout_seconds          = 1800
    schedule_expression      = "0 6 * * *"
  }

  assert {
    condition     = terraform_data.backfill[0].triggers_replace == { start_date = "2026-04-01", end_date = "2026-09-30" } && terraform_data.backfill[0].input == run.backfill_explicit_range.backfill_args
    error_message = "Upgrades and unrelated changes must not alter the backfill and run it again."
  }
}

run "supports_single_day_backfill" {
  command = plan

  variables {
    backfill_enabled    = true
    backfill_start_date = "2026-04-01"
    backfill_end_date   = "2026-04-01"
  }

  assert {
    condition     = terraform_data.backfill[0].input == "--mode=backfill,--start-date=2026-04-01,--end-date=2026-04-01"
    error_message = "Equal dates must backfill one day."
  }
}

run "supports_400_day_backfill" {
  command = plan

  variables {
    backfill_enabled    = true
    backfill_start_date = "2025-01-01"
    backfill_end_date   = "2026-02-04"
  }
}

run "allows_older_collector_without_backfill" {
  command = plan

  variables {
    artifact_version = "1.1.0"
  }
}

run "rejects_backfill_without_start" {
  command = plan

  variables {
    backfill_enabled  = true
    backfill_end_date = "2026-09-30"
  }

  expect_failures = [terraform_data.backfill]
}

run "rejects_backfill_without_end" {
  command = plan

  variables {
    backfill_enabled    = true
    backfill_start_date = "2026-04-01"
  }

  expect_failures = [terraform_data.backfill]
}

run "rejects_reversed_backfill_range" {
  command = plan

  variables {
    backfill_enabled    = true
    backfill_start_date = "2026-09-30"
    backfill_end_date   = "2026-04-01"
  }

  expect_failures = [terraform_data.backfill]
}

run "rejects_backfill_over_400_days" {
  command = plan

  variables {
    backfill_enabled    = true
    backfill_start_date = "2025-01-01"
    backfill_end_date   = "2026-02-05"
  }

  expect_failures = [terraform_data.backfill]
}

run "rejects_backfill_on_older_collector" {
  command = plan

  variables {
    backfill_enabled = true
    artifact_version = "1.1.0"
  }

  expect_failures = [terraform_data.backfill]
}

run "rejects_invalid_backfill_timeout" {
  command = plan

  variables {
    backfill_timeout_seconds = 30
  }

  expect_failures = [var.backfill_timeout_seconds]
}

run "rejects_invalid_start_date" {
  command = plan

  variables {
    backfill_start_date = "2020-02-30"
  }

  expect_failures = [var.backfill_start_date]
}

run "rejects_invalid_end_date_format" {
  command = plan

  variables {
    backfill_end_date = "30-06-2020"
  }

  expect_failures = [var.backfill_end_date]
}

run "derives_export_table_and_supports_existing_dataset" {
  command = plan

  variables {
    bigquery_table                = null
    create_billing_export_dataset = false
  }

  assert {
    condition     = length(google_bigquery_dataset.billing_export) == 0
    error_message = "Dataset creation must be disabled when the caller supplies an existing export dataset."
  }

  assert {
    condition     = one([for env in google_cloud_run_v2_job.collector.template[0].template[0].containers[0].env : env if env.name == "BIGQUERY_TABLE"]).value == "gcp_billing_export_v1_ABCDEF_ABCDEF_ABCDEF"
    error_message = "The standard export table name must be derived from the billing account ID when omitted."
  }
}

run "rejects_retired_ingestion_path" {
  command = plan

  variables {
    empirik_api_url = "https://api.manifestit.tech/api/v1/client/cost"
  }

  expect_failures = [var.empirik_api_url]
}

run "rejects_lookalike_ingestion_domain" {
  command = plan

  variables {
    empirik_api_url = "https://manifestit.tech.example.com/client/cost"
  }

  expect_failures = [var.empirik_api_url]
}

run "rejects_empty_api_key" {
  command = plan

  variables {
    mit_api_key = ""
  }

  expect_failures = [var.mit_api_key]
}

run "rejects_invalid_cost_source_id" {
  command = plan

  variables {
    cost_source_id = 0
  }

  expect_failures = [var.cost_source_id]
}

run "rejects_invalid_billing_identifiers" {
  command = plan

  variables {
    bigquery_table     = "billing-export.*"
    billing_account_id = "not-an-account"
  }

  expect_failures = [var.bigquery_table, var.billing_account_id]
}