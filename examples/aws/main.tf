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

  empirik_api_url = "https://dev.api.manifestit.tech/api/v1/cloud-cost"
  org_key         = "customer-org-key"
  x_api_key       = "<API_KEY_PLACEHOLDER>"

  tags = {
    Application = "manifest-cloud-cost"
    ManagedBy   = "Terraform"
  }
}
