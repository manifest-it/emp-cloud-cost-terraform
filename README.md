# empirik Cloud Cost Terraform

Public Terraform modules for deploying empirik cloud cost connectors into a
customer's cloud environment. Runtime binaries remain private, immutable, and
versioned in JFrog Artifactory.

## Layout

```text
modules/
  aws/       AWS Lambda and EventBridge Scheduler connector
  gcp/       Reserved for the future GCP connector
examples/
  aws/       Minimal AWS module usage
```

AWS and GCP are independent modules. They do not share provider conditionals,
state, or deployment resources.

## AWS usage

Pin both the Terraform repository tag and the immutable runtime artifact:

```hcl
module "manifest_cloud_cost_aws" {
  source = "git::https://github.com/manifest-it/emp-cloud-cost-terraform.git//modules/aws?ref=aws-terraform-v0.1.0"

  artifact_version      = "0.2.2"
  jfrog_artifactory_url = "https://manifestit.jfrog.io/artifactory"
  jfrog_repository      = "mit-cloud-cost-agent"

  empirik_api_url = "https://dev.api.manifestit.tech/api/v1/cloud-cost"
  org_key         = "customer-org-key"
  x_api_key       = "<API_KEY_PLACEHOLDER>"

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
- `x_api_key` is sensitive but is stored in Terraform state because Lambda
  environment variables are Terraform-managed. Protect the state accordingly.
- Generated state, plans, `.tfvars`, and downloaded artifacts are ignored.

The module repository contains no collector source, binaries, credentials,
customer identifiers, or Manifest production configuration.

## License

Apache License 2.0. See [LICENSE.txt](LICENSE.txt).
