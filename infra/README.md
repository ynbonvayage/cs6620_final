# SecureGate — Infrastructure (Terraform)

This is the Infrastructure-as-Code layer for SecureGate, a cloud-native security
gateway. Everything below is created from a single `terraform apply` — no manual
console clicking.

## What this provisions

| Area      | Resources |
|-----------|-----------|
| Network   | VPC, 2 public + 2 private subnets (2 AZs), Internet Gateway, single NAT Gateway, route tables |
| Compute   | Launch template (Amazon Linux 2023, IMDSv2), Auto Scaling Group across private subnets, target-tracking CPU policy |
| Ingress   | Internet-facing Application Load Balancer, HTTP listener, target group with `/health` checks |
| Identity  | EC2 instance role + profile (S3 / DynamoDB / SNS / SSM), GitHub Actions **OIDC** provider + CI role (keyless) |
| Storage   | S3 reports bucket (versioned, encrypted, Glacier lifecycle, public access blocked) |
| Data      | DynamoDB `scans` table (+ GSI for "latest N scans per repo") and `repos` registry |
| Messaging | SNS topics for HIGH-severity vuln alerts and job failures |

Security groups enforce: internet → ALB (80 only), ALB → instances (app port
only). Instances sit in **private** subnets and reach the internet via NAT.

## Project structure

The root module wires four sub-modules together; each maps to a team ownership
boundary.

```
main.tf         root: AMI/caller-identity data sources + module wiring
variables.tf    all inputs (region, CIDRs, instance type, ASG sizes, github_repo)
versions.tf     provider + version pins, default tags
outputs.tf      ALB DNS, bucket, table names, role ARNs (re-exported from modules)

modules/
  network/   VPC, subnets, IGW, NAT, route tables, security groups, ALB, TG, listener
  compute/   launch template (IMDSv2), ASG, CPU scaling policy, user_data.sh.tpl
  iam/       LabInstanceProfile data source + create_iam-guarded roles + GitHub OIDC
  data/      S3 reports bucket, DynamoDB scans + repos, SNS vuln/failure topics
```

Ownership: `network`, `compute`, `iam` are Rong's. `data` is provisioned by Rong but its
schema/lifecycle/alert design and the portal/CloudWatch on top are Na Yin's.

## Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # optional: set alert_email, github_repo
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Then hit the load balancer:

```bash
curl http://$(terraform output -raw alb_dns_name)/health   # -> ok
```

## Tear down (after recording)

```bash
terraform destroy
```

## Cost note

The NAT Gateway and ALB bill hourly (a few US cents/hour); EC2 is `t3.micro`.
A short demo run is well under $1. Run `terraform destroy` when finished.

## Known follow-ups

- Move state to an S3 backend + DynamoDB lock table (currently local state).
- Add CloudWatch alarms (owned by Na Yin) wired to the `failure-alerts` topic.
