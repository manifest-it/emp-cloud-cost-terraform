terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "manifest_cloud_cost_aws" {
  source = "../../modules/aws"

  expected_management_account_id = "123456789012"
  artifact_version               = "0.2.2"
  jfrog_artifactory_url          = "https://manifestit.jfrog.io/artifactory"
  jfrog_repository               = "mit-cloud-cost-agent"

  victoriametrics_import_url       = "https://customer.metrics.manifestit.io/api/v1/import/prometheus"
  victoriametrics_token_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:manifest-cloud-cost-EXAMPLE"

  tags = {
    Application = "manifest-cloud-cost"
    ManagedBy   = "Terraform"
  }
}
