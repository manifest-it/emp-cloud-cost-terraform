# AWS Cloud Cost Connector Module

This module downloads an immutable AWS collector artifact from JFrog, verifies
its SHA-256 checksum and keyless Sigstore bundle, copies it into customer-owned
S3, and deploys the Lambda runtime, IAM, logs, EventBridge Scheduler schedules
(daily and optional one-time backfill), and a dead-letter queue.

## Architecture

```text
JFrog -> verified ZIP in customer S3
Daily schedule    {"mode":"daily"}    \
                                        -> Lambda -> Cost Explorer -> EMP API
One-time schedule {"mode":"backfill"} /           -> CloudWatch Logs
Scheduler delivery failures and failed async invocations -> SQS dead-letter queue
```

## Resources and permissions

The module creates a private versioned S3 artifact bucket, Lambda, CloudWatch
log group, daily EventBridge schedule, optional one-time backfill schedule,
asynchronous-invocation failure destination, encrypted SQS dead-letter queue, and dedicated
Lambda/Scheduler IAM roles. It creates no networking resources.

The Terraform identity must manage those services, create IAM roles and
policies, call `sts:GetCallerIdentity`, and use `iam:PassRole`. The Lambda role
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

The same Lambda serves two EventBridge Scheduler schedules. Each schedule sends
a JSON payload that selects the collector mode:

| Schedule | Expression | Payload |
| --- | --- | --- |
| `<name_prefix>` (always) | `schedule_expression` (daily cron) | `{"mode":"daily"}` - collects N-2 |
| `<name_prefix>-backfill` (when `backfill_enabled`) | `at(backfill_schedule_at)` | `{"mode":"backfill","days":180}` or `{"mode":"backfill","start_date":"...","end_date":"..."}` |

Enable a backfill with a future run time in `schedule_timezone`:

```hcl
backfill_enabled     = true
backfill_schedule_at = "2026-11-02T03:00:00" # local time, no offset
backfill_days        = 180                   # ends at N-3, 1-400 days

# Or an explicit inclusive range instead of backfill_days (end must be <= N-3):
# backfill_start_date = "2026-01-01"
# backfill_end_date   = "2026-06-30"
```

Lifecycle:

- `apply` creates the one-time schedule; it fires once at `backfill_schedule_at`.
- After running, the schedule remains in AWS with no further invocations
  (`action_after_completion = "NONE"`), so Terraform does not drift or recreate
  and replay it.
- To run another backfill, change `backfill_schedule_at` (and the range) and apply.
- To clean up, set `backfill_enabled = false` and apply.

By default the backfill ends at N-3 so it never overlaps the daily N-2 run. The
collector issues one Cost Explorer query for the whole range (with a seven-day
anomaly baseline) and sends all days in one batched EMP push.
Dates Cost Explorer omits are not synthesized as zero-cost samples. Backfilled
samples omit live-run duration and staleness metrics. EMP pushes are
idempotent, so retrying a failed backfill is safe.

Operational guidance:

- Requires a collector `artifact_version` that supports the `mode` payload. Older
  collectors ignore the payload and run a daily collection instead.
- Set `lambda_timeout_seconds = 900` while backfilling large ranges.
- The Lambda uses reserved concurrency `1`. Schedule the backfill at least an hour
  away from the daily cron; an overlapping invocation is throttled and retried.
- Failed asynchronous invocations are retried twice and then sent to the
  dead-letter queue, alongside Scheduler delivery failures.
- Terraform warns when `backfill_schedule_at` appears to be in the past.

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
