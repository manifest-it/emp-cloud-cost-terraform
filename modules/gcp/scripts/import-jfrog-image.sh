#!/usr/bin/env bash
set -euo pipefail

: "${JFROG_ARTIFACTORY_URL:?Set JFROG_ARTIFACTORY_URL}"
: "${JFROG_REPOSITORY:?Set JFROG_REPOSITORY}"
: "${ARTIFACT_VERSION:?Set ARTIFACT_VERSION}"
: "${TARGET_IMAGE:?Set TARGET_IMAGE}"
: "${JFROG_ACCESS_TOKEN:?Set a short-lived, read-only JFROG_ACCESS_TOKEN before running Terraform}"

if [[ ! "${JFROG_ARTIFACTORY_URL}" =~ ^https://.+/artifactory$ ]]; then
  printf 'JFrog URL must use HTTPS and end in /artifactory\n' >&2
  exit 1
fi
if [[ ! "${JFROG_REPOSITORY}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'invalid JFrog repository name\n' >&2
  exit 1
fi
if [[ ! "${ARTIFACT_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
  printf 'artifact version must be semantic versioning without a v prefix\n' >&2
  exit 1
fi
if [[ ! "${TARGET_IMAGE}" =~ ^[a-z0-9-]+-docker\.pkg\.dev/[a-z][a-z0-9-]+/[a-z][a-z0-9-]+/[a-z][a-z0-9-]+:[0-9A-Za-z.+-]+$ ]]; then
  printf 'target image must be an Artifact Registry image with an immutable version tag\n' >&2
  exit 1
fi

for command_name in cosign crane curl gcloud jq shasum tar; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf '%s is required\n' "${command_name}" >&2
    exit 1
  }
done

ARTIFACT_URL="${JFROG_ARTIFACTORY_URL}/${JFROG_REPOSITORY}/gcp/${ARTIFACT_VERSION}/gcp-connector.oci.tar"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT
CURL_CONFIG="${TEMP_DIR}/curl.conf"
LAYOUT_DIR="${TEMP_DIR}/layout"
export DOCKER_CONFIG="${TEMP_DIR}/docker"

umask 077
mkdir -p "${DOCKER_CONFIG}"
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

curl --config "${CURL_CONFIG}" --max-time 600 --output "${TEMP_DIR}/image.oci.tar" "${ARTIFACT_URL}"
curl --config "${CURL_CONFIG}" --max-time 30 --output "${TEMP_DIR}/image.oci.tar.sha256" "${ARTIFACT_URL}.sha256"
curl --config "${CURL_CONFIG}" --max-time 30 --output "${TEMP_DIR}/image.oci.tar.sigstore.json" "${ARTIFACT_URL}.sigstore.json"

EXPECTED_SHA256="$(awk 'NR == 1 { print $1 }' "${TEMP_DIR}/image.oci.tar.sha256")"
if [[ ! "${EXPECTED_SHA256}" =~ ^[0-9a-f]{64}$ ]]; then
  printf 'JFrog checksum file is invalid\n' >&2
  exit 1
fi
ACTUAL_SHA256="$(shasum -a 256 "${TEMP_DIR}/image.oci.tar" | awk '{ print $1 }')"
if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
  printf 'JFrog artifact checksum verification failed\n' >&2
  exit 1
fi

cosign verify-blob \
  --bundle "${TEMP_DIR}/image.oci.tar.sigstore.json" \
  --certificate-identity "https://github.com/manifest-it/mit-cloud-cost/.github/workflows/external-gcp-release.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "${TEMP_DIR}/image.oci.tar" >/dev/null

mkdir -p "${LAYOUT_DIR}"
tar -xf "${TEMP_DIR}/image.oci.tar" -C "${LAYOUT_DIR}"
if [[ ! -f "${LAYOUT_DIR}/oci-layout" || ! -f "${LAYOUT_DIR}/index.json" ]]; then
  printf 'release artifact is not a valid OCI image layout\n' >&2
  exit 1
fi
jq -e '.schemaVersion == 2 and (.manifests | length == 1)' "${LAYOUT_DIR}/index.json" >/dev/null

REGISTRY_HOST="${TARGET_IMAGE%%/*}"
gcloud auth print-access-token | crane auth login "${REGISTRY_HOST}" \
  --username oauth2accesstoken \
  --password-stdin >/dev/null
crane push "${LAYOUT_DIR}" "${TARGET_IMAGE}"

printf 'Imported verified GCP connector %s into %s\n' "${ARTIFACT_VERSION}" "${TARGET_IMAGE}"