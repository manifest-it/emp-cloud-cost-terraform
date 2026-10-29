# GCP connector example

This example deploys the GCP cloud cost collector as a scheduled Cloud Run Job.
Copy it into a separate root module and pin the module source to a released
`gcp-terraform-vX.Y.Z` tag before deployment.

See `modules/gcp/README.md` for prerequisites, required inputs, permissions,
manual execution, and secure state requirements.

The example exposes `backfill_enabled` (default `false`),
`backfill_start_date`, and `backfill_end_date`. To replay historical data,
supply both inclusive dates in `YYYY-MM-DD` format and enable the flag.
Use a released collector image that supports date-range backfill. Apply,
execute the job manually, then disable the flag and apply again to restore
daily collection. See the module's historical backfill section for details.
