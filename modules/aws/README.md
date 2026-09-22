# AWS Cloud Cost Connector Module

This module downloads an immutable AWS collector artifact from JFrog, verifies
its checksum, copies it into customer-owned S3, and deploys the Lambda runtime,
IAM, logs, EventBridge Scheduler, and scheduler dead-letter queue.

## Prerequisites

- Terraform 1.6 or newer
- AWS management-account credentials
- An AWS provider configured by the calling root module
- `curl`, `openssl`, `shasum`, and `unzip`
- A short-lived JFrog token with read access to
  `mit-cloud-cost-agent/aws/<artifact_version>/`

```bash
export JFROG_ACCESS_TOKEN="<read-only-token>"
```

## Example

See [`../../examples/aws`](../../examples/aws) for a complete module block.

Run:

```bash
terraform init
terraform plan
terraform apply
```

The JFrog token is used only by the local download helper during planning and
application. It is not stored in Terraform state or deployed to Lambda. The
collector authenticates to the EMP API with the UI-provided `org_key` and
`x_api_key`. The API key is marked sensitive, but Terraform stores it in state
as part of the Lambda environment. Store Terraform state securely.

## Versioning

Pin an `aws-terraform-vX.Y.Z` repository tag in the module `source` and set
`artifact_version` to an immutable collector version. Release Please maintains
provider-specific release PRs from Conventional Commits under `modules/aws`.
Merging the AWS release PR creates the GitHub release and tag. Upgrade the
Terraform module and collector runtime independently and review the plan before
applying.
