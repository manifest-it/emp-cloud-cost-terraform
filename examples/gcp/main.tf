terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 8.5.0"
    }
  }
}

provider "google" {
  project = var.deployment_project_id
  region  = var.region
}

variable "deployment_project_id" { type = string }
variable "billing_export_project_id" { type = string }
variable "bigquery_query_project_id" { type = string }
variable "billing_account_id" { type = string }
variable "bigquery_dataset" { type = string }
variable "bigquery_table" { type = string }
variable "org_key" { type = string }
variable "mit_api_key" {
  type      = string
  sensitive = true
}
variable "region" {
  type    = string
  default = "us-central1"
}

module "manifest_cloud_cost_gcp" {
  source = "../../modules/gcp"

  deployment_project_id     = var.deployment_project_id
  billing_export_project_id = var.billing_export_project_id
  bigquery_query_project_id = var.bigquery_query_project_id
  bigquery_dataset          = var.bigquery_dataset
  bigquery_table            = var.bigquery_table
  billing_account_id        = var.billing_account_id

  artifact_version      = "1.0.0"
  jfrog_artifactory_url = "https://manifestit.jfrog.io/artifactory"
  jfrog_repository      = "mit-cloud-cost-agent"

  empirik_api_url  = "https://customer.api.manifestit.tech/client/cost"
  org_key          = var.org_key
  mit_api_key      = var.mit_api_key
  environment_name = "production"
  region           = var.region
}

output "cloud_run_job_name" {
  value = module.manifest_cloud_cost_gcp.cloud_run_job_name
}