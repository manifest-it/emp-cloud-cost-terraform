#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID}"
: "${REGION:?Set REGION}"
: "${JOB_NAME:?Set JOB_NAME}"
: "${JOB_ARGS:?Set JOB_ARGS}"
: "${TASK_TIMEOUT:?Set TASK_TIMEOUT}"
: "${WAIT:?Set WAIT}"

command -v gcloud >/dev/null 2>&1 || {
  printf 'gcloud CLI is required to execute the backfill\n' >&2
  exit 1
}

# Fail fast if there is already an active running execution
ACTIVE_EXECUTIONS="$(gcloud run jobs executions list \
  --job="${JOB_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --filter="status.conditions.status:Unknown" \
  --format="value(metadata.name)" \
  --limit=1 2>/dev/null || true)"

if [[ -n "${ACTIVE_EXECUTIONS}" ]]; then
  printf 'Job %s already has an active execution (%s). Wait for it to finish before backfilling.\n' "${JOB_NAME}" "${ACTIVE_EXECUTIONS}" >&2
  exit 1
fi

CMD=(
  gcloud run jobs execute "${JOB_NAME}"
  --project="${PROJECT_ID}"
  --region="${REGION}"
  --args="${JOB_ARGS}"
  --task-timeout="${TASK_TIMEOUT}"
)

if [[ "${WAIT}" == "true" ]]; then
  CMD+=(--wait)
fi

printf 'Starting backfill execution for job %s with args: %s...\n' "${JOB_NAME}" "${JOB_ARGS}"
"${CMD[@]}"
