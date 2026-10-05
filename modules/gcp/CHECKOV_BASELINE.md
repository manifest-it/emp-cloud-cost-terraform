# Checkov Baseline

This baseline records findings reviewed for the initial external GCP connector.
It is not copied from another repository and must not grow without review.

- **Owner:** External connector maintainers
- **Recorded:** 2026-10-05
- **Review by:** 2027-04-05

## Accepted Findings

| Resource | Checks | Rationale and residual risk |
| --- | --- | --- |
| Artifact Registry repository | `CKV_GCP_84` | Stores only the exact OCI image whose SHA-256 and keyless Sigstore bundle Terraform verifies before import. Tags are immutable, Google encrypts the repository at rest, and the repository is removed with the connector. A customer-managed key would add project-specific key creation, IAM, rotation, and destruction ownership to a reproducible staging artifact. Residual risk: the vendor cannot independently control the encryption key policy or rotation. |
| BigQuery billing export dataset | `CKV_GCP_81` | Google encrypts the dataset at rest with Google-managed keys. The connector module must not impose ownership of customer KMS key creation, rotation, IAM, recovery, or destruction, and Google Cloud KMS key rings cannot be deleted. Customers that require CMEK can supply an existing export dataset configured under their key policy and set `create_billing_export_dataset = false`. Residual risk: customers using the managed dataset cannot independently control its encryption-key policy or rotation. |

At review, either remediate the finding or renew it with current architecture,
cost, provider guidance, and explicit owner approval. Remove remediated checks
from `.checkov.baseline` immediately.
