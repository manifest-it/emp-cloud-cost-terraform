# Checkov Baseline

This baseline records findings reviewed for the initial external AWS connector.
It is not copied from another repository and must not grow without review.

- **Owner:** External connector maintainers
- **Recorded:** 2026-09-21
- **Review by:** 2027-03-21

## Accepted Findings

| Resource | Checks | Rationale and residual risk |
| --- | --- | --- |
| CloudWatch log group | `CKV_AWS_158`, `CKV_AWS_338` | Uses AWS-managed encryption and vendor-configurable retention (30 days by default). A customer-managed key and one-year retention would add cost and key lifecycle ownership. Residual risk: shorter evidence retention and no customer-controlled key. |
| Lambda function | `CKV_AWS_116`, `CKV_AWS_117`, `CKV_AWS_173`, `CKV_AWS_272`, `CKV_AWS_50` | The scheduler has a DLQ and retry policy; Lambda remains outside a VPC for outbound HTTPS without NAT; environment values are non-secret references; artifacts are checksum-verified, signed, and attested; X-Ray is not enabled for this daily batch. Residual risk: no Lambda-native DLQ, CMK, code-signing configuration, VPC boundary, or traces. |
| S3 artifact bucket | `CKV2_AWS_61`, `CKV2_AWS_62`, `CKV_AWS_144`, `CKV_AWS_145`, `CKV_AWS_18` | The staging bucket is private, versioned, blocks public access, denies insecure transport, and uses SSE-S3. Notification, access logging, cross-region replication, CMK encryption, and lifecycle rules are not required for the reproducible runtime ZIP. Residual risk: no independent access-log trail or regional replica. |
| EventBridge Scheduler | `CKV_AWS_297` | Uses provider-managed encryption rather than a customer-managed key. Residual risk: the vendor cannot independently control schedule-data key policy or rotation. |

At review, either remediate each finding or renew it with current architecture,
cost, provider guidance, and explicit owner approval. Remove remediated checks
from `.checkov.baseline` immediately.
