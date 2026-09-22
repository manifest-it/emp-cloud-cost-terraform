#!/usr/bin/env bash
set -euo pipefail

JFROG_ARTIFACTORY_URL="${1:-}"
JFROG_REPOSITORY="${2:-}"
VERSION="${3:-}"
OUTPUT_PATH="${4:-}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
  printf 'artifact version must be semantic versioning without a v prefix\n' >&2
  exit 1
fi

if [[ ! "${JFROG_ARTIFACTORY_URL}" =~ ^https://.+/artifactory$ ]]; then
  printf 'JFrog URL must use HTTPS and end in /artifactory\n' >&2
  exit 1
fi

if [[ ! "${JFROG_REPOSITORY}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'invalid JFrog repository name\n' >&2
  exit 1
fi

: "${JFROG_ACCESS_TOKEN:?Set a short-lived, read-only JFROG_ACCESS_TOKEN before running Terraform}"

for command_name in curl shasum unzip openssl; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf '%s is required\n' "${command_name}" >&2
    exit 1
  }
done

ARTIFACT_URL="${JFROG_ARTIFACTORY_URL}/${JFROG_REPOSITORY}/aws/${VERSION}/bootstrap.zip"
CHECKSUM_URL="${ARTIFACT_URL}.sha256"
OUTPUT_DIR="$(dirname "${OUTPUT_PATH}")"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT
CURL_CONFIG="${TEMP_DIR}/curl.conf"

umask 077
cat > "${CURL_CONFIG}" <<EOF
header = "Authorization: Bearer ${JFROG_ACCESS_TOKEN}"
fail
silent
show-error
location
retry = 3
retry-all-errors
connect-timeout = 10
EOF

mkdir -p "${OUTPUT_DIR}"

curl --config "${CURL_CONFIG}" --max-time 300 \
  --output "${TEMP_DIR}/bootstrap.zip" \
  "${ARTIFACT_URL}"

curl --config "${CURL_CONFIG}" --max-time 30 \
  --output "${TEMP_DIR}/bootstrap.zip.sha256" \
  "${CHECKSUM_URL}"

EXPECTED_SHA256="$(awk 'NR == 1 { print $1 }' "${TEMP_DIR}/bootstrap.zip.sha256")"
if [[ ! "${EXPECTED_SHA256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
  printf 'JFrog checksum file is invalid\n' >&2
  exit 1
fi

ACTUAL_SHA256="$(shasum -a 256 "${TEMP_DIR}/bootstrap.zip" | awk '{ print $1 }')"
if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
  printf 'JFrog artifact checksum verification failed\n' >&2
  exit 1
fi

if [[ "$(unzip -Z1 "${TEMP_DIR}/bootstrap.zip")" != "bootstrap" ]]; then
  printf 'Lambda archive must contain exactly one file named bootstrap\n' >&2
  exit 1
fi

mv "${TEMP_DIR}/bootstrap.zip" "${OUTPUT_PATH}"
SHA256_BASE64="$(openssl dgst -sha256 -binary "${OUTPUT_PATH}" | openssl base64 -A)"

printf '{"version":"%s","sha256":"%s","sha256_base64":"%s"}\n' \
  "${VERSION}" "${ACTUAL_SHA256}" "${SHA256_BASE64}"