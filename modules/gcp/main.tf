locals {
  job_name             = "${var.resource_prefix}-collector"
  scheduler_name       = "${var.resource_prefix}-daily"
  repository_id        = "${var.resource_prefix}-artifacts"
  runtime_account_id   = "${substr(var.resource_prefix, 0, 18)}-runtime"
  scheduler_account_id = "${substr(var.resource_prefix, 0, 16)}-scheduler"
  billing_export_table = coalesce(var.bigquery_table, "gcp_billing_export_v1_${replace(var.billing_account_id, "-", "_")}")
  image_uri            = "${var.region}-docker.pkg.dev/${var.deployment_project_id}/${local.repository_id}/gcp-cloud-cost-connector:${var.artifact_version}"
  run_uri              = "https://run.googleapis.com/v2/projects/${var.deployment_project_id}/locations/${var.region}/jobs/${local.job_name}:run"
  deployment_services = toset([
    "artifactregistry.googleapis.com",
    "cloudscheduler.googleapis.com",
    "logging.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
  ])
  runtime_environment = {
    BILLING_ACCOUNT_ID        = var.billing_account_id
    BILLING_EXPORT_PROJECT_ID = var.billing_export_project_id
    BIGQUERY_QUERY_PROJECT_ID = var.bigquery_query_project_id
    BIGQUERY_DATASET          = var.bigquery_dataset
    BIGQUERY_TABLE            = local.billing_export_table
    CONNECTOR_VERSION         = var.artifact_version
    ENVIRONMENT_NAME          = var.environment_name
    TIMEZONE                  = var.timezone
    EMPIRIK_API_URL           = var.empirik_api_url
    ORG_KEY                   = var.org_key
    PROJECT_ALLOWLIST         = join(",", var.project_allowlist)
    PROJECT_DENYLIST          = join(",", var.project_denylist)
    EVALUATION_LAG_DAYS       = tostring(var.evaluation_lag_days)
    ANOMALY_THRESHOLD_PCT     = tostring(var.anomaly_threshold_pct)
    MIN_ABSOLUTE_DELTA_USD    = tostring(var.min_absolute_delta_usd)
    MIN_BASELINE_USD          = tostring(var.min_baseline_usd)
  }
  default_labels = merge({
    application = "emp-cloud-cost"
    managed_by  = "terraform"
    provider    = "gcp"
  }, var.labels)
}

resource "google_project_service" "deployment" {
  for_each = var.manage_project_services ? local.deployment_services : toset([])

  project            = var.deployment_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service" "bigquery" {
  for_each = var.manage_project_services ? toset([var.billing_export_project_id, var.bigquery_query_project_id]) : toset([])

  project            = each.value
  service            = "bigquery.googleapis.com"
  disable_on_destroy = false
}

resource "google_bigquery_dataset" "billing_export" {
  count = var.create_billing_export_dataset ? 1 : 0

  project                    = var.billing_export_project_id
  dataset_id                 = var.bigquery_dataset
  friendly_name              = "EMP Cloud Billing export"
  description                = "Standard Cloud Billing export consumed by the EMP cloud cost connector."
  location                   = var.billing_export_dataset_location
  delete_contents_on_destroy = var.billing_export_delete_contents_on_destroy
  labels                     = local.default_labels

  depends_on = [google_project_service.bigquery]
}

resource "google_artifact_registry_repository" "collector" {
  project       = var.deployment_project_id
  location      = var.region
  repository_id = local.repository_id
  description   = "Immutable EMP GCP cloud cost collector images"
  format        = "DOCKER"
  labels        = local.default_labels

  docker_config {
    immutable_tags = true
  }

  depends_on = [google_project_service.deployment]
}

resource "terraform_data" "collector_image" {
  triggers_replace = [
    var.artifact_version,
    var.jfrog_artifactory_url,
    var.jfrog_repository,
    local.image_uri,
  ]

  provisioner "local-exec" {
    command = "${path.module}/scripts/import-jfrog-image.sh"
    environment = {
      JFROG_ARTIFACTORY_URL = var.jfrog_artifactory_url
      JFROG_REPOSITORY      = var.jfrog_repository
      ARTIFACT_VERSION      = var.artifact_version
      TARGET_IMAGE          = local.image_uri
    }
  }

  depends_on = [google_artifact_registry_repository.collector]
}

resource "google_service_account" "runtime" {
  project      = var.deployment_project_id
  account_id   = local.runtime_account_id
  display_name = "EMP GCP cloud cost collector runtime"
  description  = "Reads the billing export and sends cost metrics to the EMP API."
}

resource "google_service_account" "scheduler" {
  project      = var.deployment_project_id
  account_id   = local.scheduler_account_id
  display_name = "EMP GCP cloud cost scheduler"
  description  = "Starts only the EMP cloud cost Cloud Run Job."
}

resource "google_bigquery_dataset_iam_member" "billing_reader" {
  project    = var.billing_export_project_id
  dataset_id = var.bigquery_dataset
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.runtime.email}"

  depends_on = [google_bigquery_dataset.billing_export]
}

resource "google_project_iam_member" "query_job_user" {
  project = var.bigquery_query_project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_project_iam_member" "runtime_logging" {
  project = var.deployment_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret" "mit_api_key" {
  project   = var.deployment_project_id
  secret_id = "${var.resource_prefix}-mit-api-key"
  labels    = local.default_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.deployment]
}

resource "google_secret_manager_secret_version" "mit_api_key" {
  secret      = google_secret_manager_secret.mit_api_key.id
  secret_data = var.mit_api_key
}

resource "google_secret_manager_secret_iam_member" "runtime_api_key" {
  project   = var.deployment_project_id
  secret_id = google_secret_manager_secret.mit_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_cloud_run_v2_job" "collector" {
  project             = var.deployment_project_id
  name                = local.job_name
  location            = var.region
  labels              = local.default_labels
  deletion_protection = false

  template {
    task_count  = 1
    parallelism = 1

    template {
      service_account = google_service_account.runtime.email
      timeout         = "${var.timeout_seconds}s"
      max_retries     = var.max_retries

      containers {
        image = local.image_uri

        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }

        dynamic "env" {
          for_each = local.runtime_environment
          content {
            name  = env.key
            value = env.value
          }
        }

        env {
          name = "MIT_API_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.mit_api_key.secret_id
              version = google_secret_manager_secret_version.mit_api_key.version
            }
          }
        }
      }
    }
  }

  depends_on = [
    terraform_data.collector_image,
    google_bigquery_dataset_iam_member.billing_reader,
    google_project_iam_member.query_job_user,
    google_project_iam_member.runtime_logging,
    google_secret_manager_secret_iam_member.runtime_api_key,
  ]
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  project  = var.deployment_project_id
  location = google_cloud_run_v2_job.collector.location
  name     = google_cloud_run_v2_job.collector.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

resource "google_cloud_scheduler_job" "collector" {
  project          = var.deployment_project_id
  region           = var.region
  name             = local.scheduler_name
  description      = "Runs the EMP GCP cloud cost collector"
  schedule         = var.schedule_expression
  time_zone        = var.schedule_timezone
  attempt_deadline = "300s"

  retry_config {
    retry_count          = 3
    min_backoff_duration = "30s"
    max_backoff_duration = "300s"
    max_doublings        = 3
  }

  http_target {
    uri         = local.run_uri
    http_method = "POST"
    body        = base64encode("{}")
    headers = {
      "Content-Type" = "application/json"
    }

    oauth_token {
      service_account_email = google_service_account.scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [
    google_cloud_run_v2_job_iam_member.scheduler_invoker,
    google_project_service.deployment,
  ]
}