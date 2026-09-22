# AWS Example

Update the placeholder values in `main.tf`, then export a short-lived,
read-only JFrog token and deploy:

Install `cosign` before applying; the module verifies the downloaded runtime's
keyless Sigstore bundle as well as its SHA-256 checksum.

```bash
export JFROG_ACCESS_TOKEN="<customer-scoped-read-only-token>"
terraform init
terraform plan -out=connector.tfplan
terraform apply connector.tfplan
unset JFROG_ACCESS_TOKEN
```

`JFROG_ACCESS_TOKEN` is intentionally an environment variable rather than a
Terraform variable, so the JFrog credential is not stored in the plan or state.
The token needs read access to
`mit-cloud-cost-agent/aws/<artifact_version>/` only.

The example deploys Lambda without VPC attachment by default. To use existing
customer networking, uncomment both VPC inputs in `main.tf`. The module does
not create networking resources. Ensure the selected subnets route outbound
traffic through NAT or equivalent egress and the security group allows outbound
TCP 443; Lambda does not receive a public IP even when placed in a public
subnet.
