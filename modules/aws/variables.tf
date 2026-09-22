variable "expected_management_account_id" {
  description = "Optional guardrail. When set, deployment fails unless the active AWS account matches this ID."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.expected_management_account_id == null || can(regex("^[0-9]{12}$", var.expected_management_account_id))
    error_message = "expected_management_account_id must be a 12-digit AWS account ID."
  }
}

variable "artifact_version" {
  description = "Immutable semantic version of the AWS connector artifact to download from JFrog."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+([+-][0-9A-Za-z.-]+)?$", var.artifact_version))
    error_message = "artifact_version must be a semantic version such as 1.0.0."
  }
}

variable "jfrog_artifactory_url" {
  description = "JFrog Artifactory base URL ending in /artifactory. Authentication is read from JFROG_ACCESS_TOKEN and is never a Terraform variable."
  type        = string

  validation {
    condition     = startswith(var.jfrog_artifactory_url, "https://") && endswith(var.jfrog_artifactory_url, "/artifactory") && !strcontains(trimprefix(var.jfrog_artifactory_url, "https://"), "@")
    error_message = "jfrog_artifactory_url must be an HTTPS URL ending in /artifactory without embedded credentials."
  }
}

variable "jfrog_repository" {
  description = "JFrog generic repository containing immutable cloud-cost connector releases."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.jfrog_repository))
    error_message = "jfrog_repository may contain only letters, digits, dots, underscores, and hyphens."
  }
}

variable "empirik_api_url" {
  description = "Full HTTPS EMP API v1 endpoint issued by Manifest."
  type        = string

  validation {
    condition     = can(regex("^https://([A-Za-z0-9-]+\\.)*(manifestit\\.io|manifestit\\.tech|empirik\\.io|empirik\\.tech)(:[0-9]+)?/api/v1(/.*)?$", var.empirik_api_url)) && !strcontains(trimprefix(var.empirik_api_url, "https://"), "@")
    error_message = "empirik_api_url must be an HTTPS /api/v1 endpoint on manifestit.io, manifestit.tech, empirik.io, empirik.tech, or one of their subdomains."
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

variable "x_api_key" {
  description = "EMP X API key supplied by the onboarding application."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.x_api_key)) > 0
    error_message = "x_api_key must not be empty."
  }
}

variable "timezone" {
  description = "IANA timezone used for billing-day boundaries."
  type        = string
  default     = "UTC"
}

variable "evaluation_lag_days" {
  description = "Completed calendar days to wait before evaluation. N-2 is recommended because daily billing data is not financially final."
  type        = number
  default     = 2

  validation {
    condition     = var.evaluation_lag_days >= 1 && var.evaluation_lag_days <= 14 && floor(var.evaluation_lag_days) == var.evaluation_lag_days
    error_message = "evaluation_lag_days must be an integer from 1 through 14."
  }
}

variable "anomaly_threshold_pct" {
  description = "Percentage increase over baseline required for an anomaly."
  type        = number
  default     = 10

  validation {
    condition     = var.anomaly_threshold_pct > 0
    error_message = "anomaly_threshold_pct must be greater than zero."
  }
}

variable "min_absolute_delta_usd" {
  description = "Absolute USD increase over baseline required for an anomaly."
  type        = number
  default     = 1

  validation {
    condition     = var.min_absolute_delta_usd >= 0
    error_message = "min_absolute_delta_usd must not be negative."
  }
}

variable "min_baseline_usd" {
  description = "Minimum baseline cost eligible for percentage anomaly detection."
  type        = number
  default     = 0.5

  validation {
    condition     = var.min_baseline_usd > 0
    error_message = "min_baseline_usd must be greater than zero."
  }
}

variable "account_allowlist" {
  description = "Optional linked-account IDs to evaluate. Empty evaluates every account not denied."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.account_allowlist : can(regex("^[0-9]{12}$", id))])
    error_message = "Every account_allowlist value must be a 12-digit AWS account ID."
  }
}

variable "account_denylist" {
  description = "Linked-account IDs that must not be evaluated. Denylist takes precedence."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.account_denylist : can(regex("^[0-9]{12}$", id))])
    error_message = "Every account_denylist value must be a 12-digit AWS account ID."
  }
}

variable "schedule_expression" {
  description = "EventBridge Scheduler expression. Default runs daily at 10:00 in schedule_timezone."
  type        = string
  default     = "cron(0 10 * * ? *)"
}

variable "schedule_timezone" {
  description = "IANA timezone applied by EventBridge Scheduler."
  type        = string
  default     = "UTC"
}

variable "lambda_timeout_seconds" {
  description = "Maximum Lambda execution time."
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout_seconds >= 30 && var.lambda_timeout_seconds <= 900
    error_message = "lambda_timeout_seconds must be from 30 through 900."
  }
}

variable "lambda_memory_mb" {
  description = "Lambda memory allocation."
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_mb >= 128 && var.lambda_memory_mb <= 10240
    error_message = "lambda_memory_mb must be from 128 through 10240."
  }
}

variable "vpc_subnet_ids" {
  description = "Existing customer subnet IDs for optional Lambda VPC attachment. Leave empty with vpc_security_group_ids for non-VPC deployment. Private subnets require outbound HTTPS through NAT or equivalent egress."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.vpc_subnet_ids : can(regex("^subnet-[0-9a-fA-F]+$", id))])
    error_message = "Every vpc_subnet_ids value must be an AWS subnet ID."
  }
}

variable "vpc_security_group_ids" {
  description = "Existing customer security group IDs for optional Lambda VPC attachment. Leave empty with vpc_subnet_ids for non-VPC deployment. At least one group must allow outbound TCP 443."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.vpc_security_group_ids : can(regex("^sg-[0-9a-fA-F]+$", id))])
    error_message = "Every vpc_security_group_ids value must be an AWS security group ID."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch-supported retention value."
  }
}

variable "tags" {
  description = "Tags applied to supported resources."
  type        = map(string)
  default     = {}
}
