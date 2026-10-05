output "cloud_run_job_name" {
  description = "Name of the deployed GCP cost collector Cloud Run Job."
  value       = google_cloud_run_v2_job.collector.name
}

output "scheduler_name" {
  description = "Name of the daily Cloud Scheduler job."
  value       = google_cloud_scheduler_job.collector.name
}

output "runtime_service_account_email" {
  description = "Least-privilege service account used by collector executions."
  value       = google_service_account.runtime.email
}

output "scheduler_service_account_email" {
  description = "Service account allowed to invoke only the collector job."
  value       = google_service_account.scheduler.email
}

output "artifact_registry_repository" {
  description = "Vendor-owned Artifact Registry repository containing the collector image."
  value       = google_artifact_registry_repository.collector.id
}

output "collector_image_uri" {
  description = "Exact immutable Artifact Registry image tag deployed to Cloud Run."
  value       = local.image_uri
}

output "connector_version" {
  description = "Exact immutable connector version deployed to GCP."
  value       = var.artifact_version
}

output "region" {
  description = "Region containing the connector runtime and scheduler."
  value       = var.region
}

output "log_filter" {
  description = "Cloud Logging filter for collector executions."
  value       = "resource.type=\"cloud_run_job\" resource.labels.job_name=\"${google_cloud_run_v2_job.collector.name}\""
}