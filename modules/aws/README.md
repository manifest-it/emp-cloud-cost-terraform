# AWS Cloud Cost Connector Module

This module downloads an immutable AWS collector artifact from JFrog, verifies
its SHA-256 checksum and keyless Sigstore bundle, copies it into customer-owned
S3, and deploys the Lambda runtime, IAM, logs, a daily EventBridge Scheduler
schedule, an optional one-time backfill invoked during `terraform apply`, and a
dead-letter queue.

## Architecture

```text
JFrog -> verified ZIP in customer S3
Daily schedule          {"mode":"daily"}    \
                                              -> Lambda -> Cost Explorer -> EMP API
terraform apply (once)  {"mode":"backfill"} /           -> CloudWatch Logs
Scheduler delivery failures and failed async invocations -> SQS dead-letter queue
```

## Resources and permissions

The module creates a private versioned S3 artifact bucket, Lambda, CloudWatch
log group, daily EventBridge schedule, optional one-time backfill invocation,
asynchronous-invocation failure destination, encrypted SQS dead-letter queue, and dedicated
Lambda/Scheduler IAM roles. It creates no networking resources.

The Terraform identity must manage those services, create IAM roles and
policies, call `sts:GetCallerIdentity`, and use `iam:PassRole`. When
`backfill_enabled` is true it also needs `lambda:InvokeFunction` on the
collector. The Lambda role
gets `ce:GetCostAndUsage`, scoped log writes, and `sqs:SendMessage` on the
module dead-letter queue for failed asynchronous invocations; VPC mode also adds
required EC2 network-interface actions. The Scheduler role can invoke only this
Lambda and send failures only to its queue.

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

## One-time historical backfill

The same Lambda serves the daily schedule and an optional one-time backfill.
Each invocation sends a JSON payload that selects the collector mode:

| Trigger | When | Payload |
| --- | --- | --- |
| `<name_prefix>` schedule (always) | `schedule_expression` (daily cron) | `{"mode":"daily"}` - collects N-2 |
| `aws_lambda_invocation.backfill` (when `backfill_enabled`) | Once, during `terraform apply` | `{"mode":"backfill","days":15}` or `{"mode":"backfill","start_date":"...","end_date":"..."}` |

Enable a backfill:

```hcl
backfill_enabled = true
backfill_days    = 15 # default; ends at N-3, 1-400 days

# Or an explicit inclusive range instead of backfill_days (end must be <= N-3):
# backfill_start_date = "2026-01-01"
# backfill_end_date   = "2026-06-30"
```

Lifecycle:

- `apply` invokes the Lambda synchronously after it is deployed and waits for
  the backfill to finish. A failed backfill fails the apply; the next apply
  retries it.
- The invocation is recorded in state and is not repeated by later applies,
  including artifact upgrades and schedule or runtime changes.
- It runs again only when `backfill_days`, `backfill_start_date`, or
  `backfill_end_date` changes, when `backfill_enabled` is turned off and on
  again, or when forced with
  `terraform apply -replace='module.<name>.aws_lambda_invocation.backfill[0]'`.
- Setting `backfill_enabled = false` only removes the record from state; it
  does not invoke the Lambda.

By default the backfill ends at N-3 so it never overlaps the daily N-2 run. The
collector issues one Cost Explorer query for the whole range (with a seven-day
anomaly baseline) and sends all days in one batched EMP push.
Dates Cost Explorer omits are not synthesized as zero-cost samples. Backfilled
samples omit live-run duration and staleness metrics. EMP pushes are
idempotent, so retrying a failed backfill is safe.

Operational guidance:

- Requires a collector `artifact_version` that supports the `mode` payload. Older
  collectors ignore the payload and run a daily collection instead.
- Set `lambda_timeout_seconds = 900` while backfilling large ranges; `apply`
  waits for up to that long.
- The Lambda uses reserved concurrency `1`. Avoid applying while the daily
  schedule is running; a throttled invocation fails the apply and can be retried.
- The backfill is synchronous, so it does not use the asynchronous retry policy
  or dead-letter queue; failures are reported by `terraform apply` and in
  CloudWatch Logs.
- Upgrading from a module version that used a `backfill_schedule_at` schedule
  removes that schedule. If `backfill_enabled` is still true, the backfill runs
  once more during the upgrade apply; set `backfill_enabled = false` first to
  skip it.

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
