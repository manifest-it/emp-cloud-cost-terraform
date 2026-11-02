# AWS Cloud Cost Connector Module

This module downloads an immutable AWS collector artifact from JFrog, verifies
its SHA-256 checksum and keyless Sigstore bundle, copies it into customer-owned
S3, and deploys the Lambda runtime, IAM, logs, EventBridge Scheduler, and
scheduler dead-letter queue.

## Architecture

```text
JFrog -> verified ZIP in customer S3
Scheduler -> Lambda -> Cost Explorer -> EMP API
                    -> CloudWatch Logs
Scheduler failures -> SQS dead-letter queue
```

## Resources and permissions

The module creates a private versioned S3 artifact bucket, Lambda, CloudWatch
log group, EventBridge schedule, encrypted SQS dead-letter queue, and dedicated
Lambda/Scheduler IAM roles. It creates no networking resources.

The Terraform identity must manage those services, create IAM roles and
policies, call `sts:GetCallerIdentity`, and use `iam:PassRole`. The Lambda role
gets `ce:GetCostAndUsage` and scoped log writes; VPC mode also adds required EC2
network-interface actions. The Scheduler role can invoke only this Lambda and
send failures only to its queue.

## Prerequisites

- Terraform 1.6 or newer
- AWS management-account credentials with the deployer permissions above
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

The JFrog token is used only by the local download helper when Terraform
evaluates the artifact data source, normally during planning. It is not stored
in Terraform state or deployed to Lambda. The
collector authenticates to the EMP API with the UI-provided `org_key` and
`mit_api_key`, returned as `mitApiKey` by Cost Source Create or Update. The API
key is marked sensitive, but Terraform stores it in state as part of the Lambda
environment. Store Terraform state securely.

The UI must also provide `cost_source_id`: the numeric `id` returned by Cost
Source Create or Update. Terraform injects it into the Lambda as
`COST_SOURCE_ID`; the collector sends it as `Mit-Cost-Source-Id` so the API can
validate the configured source and scope.

## Historical backfill

Backfill is disabled by default, preserving daily collection. With a collector
version that supports date-range backfill, set:

```hcl
backfill_enabled    = true
backfill_start_date = "2026-04-01"
backfill_end_date   = "2026-04-30"
```

Terraform passes these as `BACKFILL_ENABLED`, `BACKFILL_START_DATE`, and
`BACKFILL_END_DATE` in the Lambda environment. Dates must be valid `YYYY-MM-DD`
values; start must not exceed end, and supplying only one is an error. If both
are omitted, the collector defaults to 15 inclusive dates ending at its daily
evaluation date (N-16 through N-2 with the default lag), calculated at execution.
End must be on or before the daily evaluation date; the collector checks this at
runtime, not at plan time.

Backfill replaces daily collection while enabled. The collector queries Cost
Explorer once for the range plus seven baseline days and sends every available
billing date to EMP in one batched request. Dates Cost Explorer omits are not
synthesized as zero-cost samples. There is no completion state, so set
`backfill_enabled = false` and apply again after the replay; otherwise every
scheduled invocation repeats it.

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
