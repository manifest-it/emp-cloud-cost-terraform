# empirik Cloud Cost Terraform

Public Terraform modules for deploying empirik cloud cost connectors into a
customer's cloud environment. Runtime binaries remain private, immutable, and
versioned in JFrog Artifactory.

## Layout

```text
modules/
  aws/       AWS Lambda and EventBridge Scheduler connector
  gcp/       GCP Cloud Run Job and Cloud Scheduler connector
examples/
  aws/       Minimal AWS module usage
  gcp/       Minimal GCP module usage
```

AWS and GCP are independent modules. They do not share provider conditionals,
state, or deployment resources.

## Architecture

```text
AWS: Scheduler -> Lambda -> Cost Explorer -> EMP API
GCP: Scheduler -> Cloud Run Job -> BigQuery billing export -> EMP API
```

| Provider | Main resources created | Runtime access |
| --- | --- | --- |
| AWS | S3 artifact bucket, Lambda, Scheduler, SQS DLQ, logs, IAM roles | Cost Explorer read and log write |
| GCP | Artifact Registry, Cloud Run Job, Scheduler, Secret Manager, service accounts | BigQuery read/query, log write, and connector-secret read |

Terraform needs permission to manage those resources and IAM bindings. See the
[AWS](modules/aws/README.md) and [GCP](modules/gcp/README.md) module READMEs for
provider-specific prerequisites.

## AWS usage

Pin both the Terraform repository tag and the immutable runtime artifact:

```hcl
variable "mit_api_key" {
  description = "One-time API key returned as mitApiKey from Cost Source Create or Update."
  type        = string
  sensitive   = true
}

module "manifest_cloud_cost_aws" {
  source = "git::https://github.com/manifest-it/emp-cloud-cost-terraform.git//modules/aws?ref=aws-terraform-v<module-version>"

  artifact_version      = "0.6.0"
  jfrog_artifactory_url = "https://manifestit.jfrog.io/artifactory"
  jfrog_repository      = "mit-cloud-cost-agent"

  empirik_api_url = "https://dev.api.manifestit.tech/client/cost"
  org_key         = "customer-org-key"
  mit_api_key     = var.mit_api_key

  # Optional existing customer VPC attachment. Omit both for non-VPC mode.
  # vpc_subnet_ids         = ["subnet-0123456789abcdef0"]
  # vpc_security_group_ids = ["sg-0123456789abcdef0"]

  # See modules/aws/README.md for the remaining required inputs.
}
```

Git sources do not support Terraform's `version` argument. The `ref` pins the
infrastructure module, while `artifact_version` pins the collector binary.
The JFrog token is intentionally not a Terraform input. Run the deployment with
the token in the caller environment:

```bash
export JFROG_ACCESS_TOKEN="<customer-scoped-read-only-token>"
terraform init
terraform plan -out=connector.tfplan
terraform apply connector.tfplan
unset JFROG_ACCESS_TOKEN
```

## GCP usage

The GCP module deploys an outbound-only Cloud Run Job with separate runtime and
scheduler service accounts. It creates the BigQuery billing-export dataset and
imports the exact CI-built OCI image into customer-owned Artifact Registry.
Google requires a billing administrator to enable the standard usage export in
the Cloud Billing console after the dataset is created.
See [modules/gcp/README.md](modules/gcp/README.md) for the complete deployment
contract and [examples/gcp](examples/gcp) for a minimal caller.

## Releases

Release Please maintains an independent release PR for each provider module.
Use Conventional Commits for changes under `modules/<provider>`:

- `fix(aws): ...` creates an AWS patch release.
- `feat(gcp): ...` creates a GCP minor release.
- `feat(azure)!: ...` creates an Azure major release.

Merging a provider release PR creates its GitHub release and immutable tag:
`aws-terraform-vX.Y.Z`, `gcp-terraform-vX.Y.Z`, or
`azure-terraform-vX.Y.Z`. Commits accumulate in the relevant release PR; they
are not published immediately on every push.

## Security model

- JFrog credentials are read only from `JFROG_ACCESS_TOKEN`; they are never
  Terraform variables and therefore are not written to plans or state.
- Terraform verifies the runtime SHA-256 and keyless Sigstore bundle before
  copying it into customer-owned cloud storage.
- The deployed runtime does not need JFrog access.
- Every provider module uses least-privilege cloud IAM and outbound HTTPS.
- AWS VPC attachment is optional and uses only customer-supplied subnets and
  security groups; the module does not create networking resources.
- `mit_api_key` is sensitive but is stored in Terraform state because the cloud
  runtime secret is Terraform-managed. Protect the state accordingly.
- Generated state, plans, `.tfvars`, and downloaded artifacts are ignored.

The module repository contains no collector source, binaries, credentials,
customer identifiers, or Manifest production configuration.

## License

Apache License 2.0. See [LICENSE.txt](LICENSE.txt).
