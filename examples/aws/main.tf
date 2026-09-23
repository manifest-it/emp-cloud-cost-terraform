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

  # Optional: refresh the 15 historical days before the normal N-2 day.
  backfill_last_15_days = false

  # Optional: attach Lambda to existing customer networking. Leave both lists
  # empty for the default non-VPC deployment. These subnets need NAT or
  # equivalent outbound HTTPS connectivity.
  # vpc_subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  # vpc_security_group_ids = ["sg-0123456789abcdef0"]

  tags = {
    Application = "manifest-cloud-cost"
    ManagedBy   = "Terraform"
  }
}
