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
  artifact_version          = "0.1.0"
  jfrog_artifactory_url     = "https://example.jfrog.io/artifactory"
  jfrog_repository          = "cloud-cost-connectors"
  empirik_api_url           = "https://api.manifestit.tech/client/cost"
  org_key                   = "test-org"
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

run "rejects_invalid_billing_identifiers" {
  command = plan

  variables {
    bigquery_table     = "billing-export.*"
    billing_account_id = "not-an-account"
  }

  expect_failures = [var.bigquery_table, var.billing_account_id]
}