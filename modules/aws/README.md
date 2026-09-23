# AWS Cloud Cost Connector Module

This module downloads an immutable AWS collector artifact from JFrog, verifies
its SHA-256 checksum and keyless Sigstore bundle, copies it into customer-owned
S3, and deploys the Lambda runtime, IAM, logs, EventBridge Scheduler, and
scheduler dead-letter queue.

## Prerequisites

- Terraform 1.6 or newer
- AWS management-account credentials
- An AWS provider configured by the calling root module
- `cosign`, `curl`, `openssl`, `shasum`, and `unzip`
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

## Optional 15-day backfill

Set `backfill_last_15_days = true` to refresh the 15 historical billing days
before the normal evaluation date. It is `false` by default. The normal
scheduled run writes N-2; historical processing covers N-17 through N-3 so the
two paths do not overlap.

The collector queries Cost Explorer once for the range and seven baseline days,
then sends every available billing date in that 15-day window to EMP in one
batched request. Dates Cost Explorer omits because no billing data exists are
not synthesized as zero-cost samples.
Backfilled samples omit live-run duration and staleness metrics. No checkpoint,
runtime S3 access, self-invocation, or additional AWS SDK client is used. With
no durable completion state, leaving the option enabled refreshes the rolling
15-day window on every scheduled invocation.

## Optional VPC attachment

By default, the Lambda is not attached to a VPC. To use an existing customer
VPC, supply both subnet and security-group IDs:

```hcl
vpc_subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
vpc_security_group_ids = ["sg-0123456789abcdef0"]
```

The module only attaches the Lambda and grants its runtime role the required
ENI permissions. It does not create or modify VPCs, subnets, route tables, NAT
gateways, VPC endpoints, or security groups. Leave both inputs empty to retain
the default non-VPC deployment. Supplying only one input fails the plan.

VPC-attached Lambda functions do not receive public IP addresses, including in
public subnets. The selected subnets must have outbound internet connectivity
through a NAT gateway or equivalent egress, and a supplied security group must
allow outbound TCP 443. This is required to reach AWS Cost Explorer and the
public EMP API. Inbound security-group rules are not required.

## Versioning

Pin an `aws-terraform-vX.Y.Z` repository tag in the module `source` and set
`artifact_version` to an immutable collector version. Release Please maintains
provider-specific release PRs from Conventional Commits under `modules/aws`.
Merging the AWS release PR creates the GitHub release and tag. Upgrade the
Terraform module and collector runtime independently and review the plan before
applying.
