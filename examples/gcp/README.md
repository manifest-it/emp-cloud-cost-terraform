# GCP connector example

This example deploys the GCP cloud cost collector as a scheduled Cloud Run Job.
Copy it into a separate root module and pin the module source to a released
`gcp-terraform-vX.Y.Z` tag before deployment.

See `modules/gcp/README.md` for prerequisites, required inputs, permissions,
manual execution, and secure state requirements.

The example exposes `backfill_enabled` (default `false`),
`backfill_start_date`, `backfill_end_date`, `backfill_wait` (default `true`),
and `backfill_timeout_seconds` (default `3600`). When enabled, `terraform apply`
executes the Cloud Run Job once with `--mode=backfill` arguments, without
changing the saved job or the daily schedule. Omitting both dates backfills 15
inclusive dates ending at N-3, calculated at execution; supply both dates for an
explicit range of at most 400 dates. Later applies do not repeat the backfill
unless the dates change or the flag is turned off and on again. It requires
collector 2.0.0 or later and a `gcloud` identity that can execute the job with
overrides, such as `roles/run.developer`. See the module's historical backfill
section for details.
