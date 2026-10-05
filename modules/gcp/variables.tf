variable "deployment_project_id" {
  description = "GCP project in which the connector runtime and scheduler are deployed."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.deployment_project_id))
    error_message = "deployment_project_id must be a valid GCP project ID."
  }
}

variable "billing_export_project_id" {
  description = "GCP project containing the existing Cloud Billing BigQuery export."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.billing_export_project_id))
    error_message = "billing_export_project_id must be a valid GCP project ID."
  }
}

variable "bigquery_query_project_id" {
  description = "GCP project billed for BigQuery query jobs."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.bigquery_query_project_id))
    error_message = "bigquery_query_project_id must be a valid GCP project ID."
  }
}

variable "bigquery_dataset" {
  description = "Existing BigQuery billing-export dataset ID."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_]+$", var.bigquery_dataset))
    error_message = "bigquery_dataset may contain only letters, digits, and underscores."
  }
}

variable "bigquery_table" {
  description = "Existing standard Cloud Billing export table ID."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_]+$", var.bigquery_table))
    error_message = "bigquery_table may contain only letters, digits, and underscores."
  }
}

variable "billing_account_id" {
  description = "Cloud Billing account ID represented by the export."
  type        = string

  validation {
    condition     = can(regex("^[A-Fa-f0-9]{6}-[A-Fa-f0-9]{6}-[A-Fa-f0-9]{6}$", var.billing_account_id))
    error_message = "billing_account_id must use the XXXXXX-XXXXXX-XXXXXX format."
  }
}

variable "artifact_version" {
  description = "Exact immutable GCP collector semantic version, without the gcp-connector-v prefix."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+([+-][0-9A-Za-z.-]+)?$", var.artifact_version))
    error_message = "artifact_version must be an exact semantic version without a v prefix."
  }
}

variable "jfrog_artifactory_url" {
  description = "HTTPS JFrog Artifactory base URL ending in /artifactory."
  type        = string

  validation {
    condition     = can(regex("^https://[^/@]+(?:\\.[^/@]+)+/artifactory$", var.jfrog_artifactory_url)) && !strcontains(trimprefix(var.jfrog_artifactory_url, "https://"), "@")
    error_message = "jfrog_artifactory_url must be a credential-free HTTPS URL ending in /artifactory."
  }
}

variable "jfrog_repository" {
  description = "JFrog generic repository containing immutable connector releases."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.jfrog_repository))
    error_message = "jfrog_repository may contain only letters, digits, dots, underscores, and hyphens."
  }
}

variable "empirik_api_url" {
  description = "Full HTTPS MIT cost-ingestion endpoint issued by Manifest."
  type        = string

  validation {
    condition     = can(regex("^https://([A-Za-z0-9-]+\\.)*(manifestit\\.io|manifestit\\.tech|empirik\\.io|empirik\\.tech)(:[0-9]+)?/client/cost/?$", var.empirik_api_url)) && !strcontains(trimprefix(var.empirik_api_url, "https://"), "@")
    error_message = "empirik_api_url must be the HTTPS /client/cost endpoint on an approved Manifest or Empirik domain."
  }
}

variable "org_key" {
  description = "EMP organization key sent with each ingestion request."
  type        = string

  validation {
    condition     = length(trimspace(var.org_key)) > 0
    error_message = "org_key must not be empty."
  }
}

variable "mit_api_key" {
  description = "MIT API key supplied by the onboarding application. Stored in Secret Manager and Terraform state."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.mit_api_key)) > 0
    error_message = "mit_api_key must not be empty."
  }
}

variable "environment_name" {
  description = "Non-secret environment label added to emitted metrics."
  type        = string

  validation {
    condition     = length(trimspace(var.environment_name)) > 0
    error_message = "environment_name must not be empty."
  }
}

variable "region" {
  description = "Region for Artifact Registry, Cloud Run Job, and Cloud Scheduler."
  type        = string
  default     = "us-central1"
}

variable "resource_prefix" {
  description = "Prefix used for connector resources."
  type        = string
  default     = "emp-cloud-cost"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.resource_prefix)) && !endswith(var.resource_prefix, "-")
    error_message = "resource_prefix must be 3-30 lowercase letters, digits, or hyphens and must not end in a hyphen."
  }
}

variable "manage_project_services" {
  description = "Whether Terraform enables required Google APIs in the deployment and query projects."
  type        = bool
  default     = true
}

variable "timezone" {
  description = "IANA timezone used for billing-day boundaries."
  type        = string
  default     = "UTC"
}

variable "evaluation_lag_days" {
  description = "Completed calendar days to wait before evaluating billing data."
  type        = number
  default     = 2

  validation {
    condition     = var.evaluation_lag_days >= 1 && floor(var.evaluation_lag_days) == var.evaluation_lag_days
    error_message = "evaluation_lag_days must be an integer of at least 1."
  }
}

variable "anomaly_threshold_pct" {
  description = "Percentage increase over baseline required for an anomaly."
  type        = number
  default     = 10

  validation {
    condition     = var.anomaly_threshold_pct > 0
    error_message = "anomaly_threshold_pct must be greater than 0."
  }
}

variable "min_absolute_delta_usd" {
  description = "Minimum absolute USD increase required for an anomaly."
  type        = number
  default     = 1

  validation {
    condition     = var.min_absolute_delta_usd >= 0
    error_message = "min_absolute_delta_usd must not be negative."
  }
}

variable "min_baseline_usd" {
  description = "Minimum baseline USD value required for anomaly evaluation."
  type        = number
  default     = 0.5

  validation {
    condition     = var.min_baseline_usd > 0
    error_message = "min_baseline_usd must be greater than 0."
  }
}

variable "project_allowlist" {
  description = "Optional GCP project IDs to include. Empty includes all projects."
  type        = list(string)
  default     = []
}

variable "project_denylist" {
  description = "Optional GCP project IDs to exclude."
  type        = list(string)
  default     = []
}

variable "schedule_expression" {
  description = "Cloud Scheduler unix-cron expression."
  type        = string
  default     = "0 10 * * *"
}

variable "schedule_timezone" {
  description = "IANA timezone used by Cloud Scheduler."
  type        = string
  default     = "UTC"
}

variable "timeout_seconds" {
  description = "Maximum duration of each Cloud Run Job attempt."
  type        = number
  default     = 900

  validation {
    condition     = var.timeout_seconds >= 60 && var.timeout_seconds <= 86400 && floor(var.timeout_seconds) == var.timeout_seconds
    error_message = "timeout_seconds must be an integer from 60 through 86400."
  }
}

variable "max_retries" {
  description = "Cloud Run task retries after a failed collector execution."
  type        = number
  default     = 1

  validation {
    condition     = var.max_retries >= 0 && var.max_retries <= 10 && floor(var.max_retries) == var.max_retries
    error_message = "max_retries must be an integer from 0 through 10."
  }
}

variable "cpu" {
  description = "Cloud Run Job CPU limit."
  type        = string
  default     = "1"

  validation {
    condition     = contains(["1", "2", "4", "6", "8"], var.cpu)
    error_message = "cpu must be one of 1, 2, 4, 6, or 8."
  }
}

variable "memory" {
  description = "Cloud Run Job memory limit."
  type        = string
  default     = "512Mi"

  validation {
    condition     = can(regex("^[1-9][0-9]*(Mi|Gi)$", var.memory))
    error_message = "memory must be a positive Mi or Gi quantity, such as 512Mi or 1Gi."
  }
}

variable "labels" {
  description = "Labels applied to supported GCP resources."
  type        = map(string)
  default     = {}
}