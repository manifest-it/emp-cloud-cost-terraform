# GCP Cloud Cost Connector Module

This module imports an immutable, signed GCP collector image from JFrog into
customer-owned Artifact Registry and deploys it as a scheduled Cloud Run Job.
It creates the BigQuery dataset used by the standard Cloud Billing export. The
collector reads the Google-created export table and sends cost metrics outbound
to the configured EMP API. It exposes no inbound application endpoint.

## Architecture

```text
Cloud Scheduler
  -> OAuth POST to Cloud Run Jobs :run API
  -> Cloud Run Job (one task, dedicated runtime identity)
  -> Terraform-managed BigQuery billing-export dataset
  -> EMP API /client/cost over HTTPS

Terraform workstation
  -> download exact OCI archive from JFrog
  -> verify SHA-256 and keyless Sigstore bundle
  -> import into customer Artifact Registry with an immutable version tag
  -> optional one-time backfill: gcloud run jobs execute --args=--mode=backfill
```

Runtime and scheduling use separate service accounts. The runtime receives
`roles/bigquery.dataViewer` on only the configured dataset,
`roles/bigquery.jobUser` on the query project, `roles/logging.logWriter` on the
deployment project, and access to only its API-key secret. The scheduler
identity receives `roles/run.invoker` on only the connector job.

## Resources and permissions

The module creates a BigQuery billing-export dataset, immutable Artifact
Registry repository, Secret Manager secret, Cloud Run Job, Cloud Scheduler job,
two service accounts, and scoped IAM bindings. It can also enable the required
APIs. It does not create projects, networking, or a public endpoint. Google
creates and populates the billing table after export enrollment.

The Terraform identity must manage those resources and IAM bindings, attach
service accounts, enable APIs when requested, and upload the verified image.
When `backfill_enabled` is true, the active `gcloud` identity must also be able
to list the job's executions and execute it with overrides, for example with
`roles/run.developer` on the job or deployment project.
The runtime receives `roles/bigquery.dataViewer`, `roles/bigquery.jobUser`,
`roles/logging.logWriter`, and secret-level
`roles/secretmanager.secretAccessor`. The scheduler receives job-level
`roles/run.invoker` only.

## Prerequisites

- Terraform 1.6 or newer
- Google credentials with the deployer permissions above
- Billing Account Costs Manager or Billing Account Administrator access for the
  one-time standard usage export enrollment
- A Google provider configured by the calling root module
- `cosign`, `crane`, `curl`, `gcloud`, `jq`, `shasum`, and `tar`
- For `backfill_enabled`, collector `artifact_version` 2.0.0 or later
- A short-lived JFrog token with read access to
  `mit-cloud-cost-agent/gcp/<artifact_version>/`

Authenticate both Terraform Application Default Credentials and the active
`gcloud` CLI identity used by the image-import and backfill helpers, then export
the JFrog token:

```bash
gcloud auth application-default login
gcloud auth login
export JFROG_ACCESS_TOKEN="<read-only-token>"
```

## Usage

Pin the module repository and collector image independently:

```hcl
module "manifest_cloud_cost_gcp" {
  source = "git::https://github.com/manifest-it/emp-cloud-cost-terraform.git//modules/gcp?ref=gcp-terraform-v<module-version>"

  deployment_project_id     = "customer-connector-project"
  billing_export_project_id = "customer-billing-export"
  bigquery_query_project_id = "customer-connector-project"
  bigquery_dataset          = "billing_export"
  billing_account_id        = "XXXXXX-XXXXXX-XXXXXX"

  create_billing_export_dataset   = true
  billing_export_dataset_location = "US"

  artifact_version      = "2.0.0"
  jfrog_artifactory_url = "https://manifestit.jfrog.io/artifactory"
  jfrog_repository      = "mit-cloud-cost-agent"

  empirik_api_url = "https://customer.api.manifestit.tech/client/cost"
  org_key         = "customer-org-key"
  cost_source_id  = var.cost_source_id
  mit_api_key     = var.mit_api_key
  environment_name = "production"
}
```

See [`../../examples/gcp`](../../examples/gcp) and
[`terraform.tfvars.example`](terraform.tfvars.example) for a complete caller
shape. Then run:

```bash
terraform init
terraform plan -out=connector.tfplan
terraform apply connector.tfplan
unset JFROG_ACCESS_TOKEN
```

## Cost source

The UI must provide `cost_source_id`: the numeric `id` returned by Cost Source
Create or Update. Terraform injects it into the Cloud Run Job as
`COST_SOURCE_ID`; the collector sends it as `Mit-Cost-Source-Id` so the API can
resolve the configured cost source.

## Required billing export enrollment

Google does not provide a public API, `gcloud` command, or Google Terraform
provider resource for standard usage cost export enrollment. After the first
apply, a billing administrator must complete this one-time Google Cloud console
step:

1. Open `terraform output -raw billing_export_setup_url`.
2. Select the configured billing account.
3. Enable **Standard usage cost** export.
4. Select the project and dataset shown by
  `terraform output -raw billing_export_dataset`, then save.

Google automatically creates the table shown by
`terraform output -raw billing_export_table`. Initial data can take hours to
appear, and the current and previous month backfill can take up to five days.
Do not run the collector until the table exists.

`JFROG_ACCESS_TOKEN` is read only by the local import helper. It is never a
Terraform input, stored in state, or deployed to GCP. The API key is marked
sensitive and stored in Secret Manager, but its secret value is necessarily
present in Terraform state. Use an encrypted, access-controlled remote backend.

## Existing resources and platform boundary

The module does not create the organization, folder, project, billing account,
VPC, subnet, NAT gateway, or public endpoint. Set
`create_billing_export_dataset = false` only when reusing an existing export
dataset. Cloud Run uses its default outbound internet path to reach Google APIs
and the EMP HTTPS endpoint.

By default, the module enables the required APIs and leaves them enabled during
destroy so shared project services are not disrupted. Set
`manage_project_services = false` when API lifecycle is managed centrally.

## Operation

The default schedule is `0 10 * * *` in UTC. The default evaluation lag is N-2:
that delay makes billing data sufficiently settled for monitoring, but it is
not financially final because Google can publish late usage and corrections.

Run the collector manually with:

```bash
gcloud run jobs execute "$(terraform output -raw cloud_run_job_name)" \
  --project="<deployment-project-id>" \
  --region="$(terraform output -raw region)" \
  --wait
```

Inspect logs with the value of the `log_filter` output. Disable the billing
export before destroy. By default, Terraform refuses to delete a non-empty
billing dataset to protect cost history. Set
`billing_export_delete_contents_on_destroy = true` only for a disposable test
deployment whose exported data may be deleted. Required Google APIs remain
enabled by design.

## Historical backfill

The Cloud Run Job serves the daily schedule and an optional one-time backfill.
The execution arguments select the collector mode:

| Trigger | When | Execution arguments |
| --- | --- | --- |
| Cloud Scheduler (always) | `schedule_expression` (daily) | none - collects N-2 |
| `terraform_data.backfill` (when `backfill_enabled`) | Once, during `terraform apply` | `--mode=backfill`, plus `--start-date` and `--end-date` for an explicit range |

Enable a backfill with collector `artifact_version` 2.0.0 or later:

```hcl
backfill_enabled = true # 15 dates ending at N-3

# Or an explicit inclusive range of at most 400 dates (end must be <= N-3):
# backfill_start_date = "2026-04-01"
# backfill_end_date   = "2026-09-30"

# backfill_wait            = true # default; apply waits for the execution
# backfill_timeout_seconds = 3600 # default; applies to this execution only
```

Lifecycle:

- After the job is deployed, `apply` runs `scripts/run-backfill.sh`, which
  calls `gcloud run jobs execute` with `--args` and `--task-timeout`. These
  overrides apply only to that execution; the saved job, its environment, and
  the daily schedule are unchanged.
- With `backfill_wait = true`, `apply` waits for the execution. A failed
  backfill fails the apply and taints `terraform_data.backfill`, so the next
  apply retries it. With `backfill_wait = false`, `apply` returns once the
  execution starts; check the result in Cloud Run, because later applies do not
  retry a failed execution.
- The execution is recorded in state and is not repeated by later applies,
  including artifact upgrades and schedule or runtime changes.
- It runs again only when `backfill_start_date` or `backfill_end_date` changes,
  when `backfill_enabled` is turned off and on again, or when forced with
  `terraform apply -replace='module.<name>.terraform_data.backfill[0]'`.
- Setting `backfill_enabled = false` only removes the record from state; it does
  not execute or cancel anything.
- If the job already has an unfinished execution, such as the daily run or an
  earlier backfill, the script fails the apply without starting another. Apply
  again after it finishes.

N-3 is the day before the daily run's evaluation date (N-2 with the default
`evaluation_lag_days`), so a backfill never overlaps the daily run. Without
dates, the collector backfills 15 dates ending at N-3, calculated at execution
from `timezone` and `evaluation_lag_days`. Explicit dates must be valid `YYYY-MM-DD`, supplied together, in
order, and span at most 400 dates; Terraform checks these during plan. The
collector rejects an end date after N-3 when it executes. It reads seven extra
days for anomaly baselines and pushes one EMP request per day with billing data.
EMP pushes are idempotent, so retrying a failed backfill is safe.

Operational guidance:

- `apply` can wait up to about `(max_retries + 1) * backfill_timeout_seconds`
  and holds the state lock meanwhile. Each task retry replays the whole range.
- Interrupting `apply` does not stop the execution. Cancel it with
  `gcloud run jobs executions cancel <execution> --project=<deployment-project-id> --region=<region>`.
- Enable backfill only after the billing export table contains the history to
  import. Missing history cannot be reconstructed, and destination retention is
  separate.
- Each pushed day logs `backfill day pushed` with `day` and `total_days`. Add
  `labels."run.googleapis.com/execution_name"="<execution>"` to the `log_filter`
  output to follow one execution.
- For a manual backfill, add `--args=--mode=backfill,--start-date=YYYY-MM-DD,--end-date=YYYY-MM-DD`
  and `--task-timeout=3600s` to the manual execution command above.

Upgrading from module 0.x removes the `BACKFILL_ENABLED`, `BACKFILL_START_DATE`,
and `BACKFILL_END_DATE` job environment variables. Daily collection no longer
depends on disabling `backfill_enabled` after a backfill. If `backfill_enabled`
is still true, the upgrade apply runs the backfill once; set it to `false` first
to skip that.

## Versioning

Pin a `gcp-terraform-vX.Y.Z` repository tag in `source` and set
`artifact_version` to an immutable collector version. Artifact Registry has
immutable tags enabled, so an existing version cannot be overwritten. Upgrade
the Terraform module and collector independently and review the plan before
applying.
