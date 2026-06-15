# SecureGate — Automated SAST Pipeline on AWS

> CS6620 Cloud Computing · Summer 2026 · Group 03
>
> **Team:** Na Yin (Member A) · Rong Huang (Member B) · Hao Ding (Member C)

Automatically scans every pull request for security vulnerabilities and **blocks merges** if HIGH severity issues are found.

---

## Architecture

```
Developer opens PR
        │
        ▼
GitHub Actions (sast.yml)
  differential scan: only JS files added/modified in this PR
        │  POST JSON payload (jq-encoded)
        ▼
API Gateway v2 (HTTP API)
  replaces Lambda Function URL — Learner Lab SCP blocks InvokeFunctionUrl
        │
        ▼
Lambda  sast-handler
  parses request → calls scanner → persists results → returns summary
        │  POST /scan/code
        ▼
ALB (public subnet) → EC2 ASG (private subnet, Docker)
  regex-based SAST engine, 11 vulnerability rule categories
        │
        ├──► DynamoDB  scan summaries (queryable by repo via GSI)
        ├──► S3        full vulnerability reports (Glacier after 30 days)
        └──► SNS       vuln-alerts (HIGH found) · failure-alerts (scanner down)
        │
        ▼
GitHub Actions posts PR comment with severity table
  HIGH > 0      → exit 1 → PR merge blocked
  scanner down  → exit 2 → PR merge blocked
  no JS changes → exit 0 → scan skipped

Dashboard (read path):
API Gateway → Lambda dashboard-api → DynamoDB + S3 → S3 static frontend
```

---

## Team Responsibilities

**Member A — Na Yin (SAST Pipeline + Data Layer)**
- Lambda orchestrator: receives scan requests via API Gateway, calls EC2 scanner, persists results to DynamoDB + S3, returns scan summary
- API Gateway v2: replaced Lambda Function URL to bypass Learner Lab SCP restriction
- GitHub Actions workflow: differential scan (only changed JS files), jq-based JSON encoding, PR comment with severity table, exit codes for blocked/pass/error states
- Data layer design: DynamoDB table schema (partition key + GSI for repo queries), S3 lifecycle policy
- CloudWatch alarm + SNS failure-alerts: notifies when all EC2 instances go unhealthy

**Member B — Rong Huang (Infrastructure)**
- Network: VPC, public/private subnets across 2 AZs, Internet Gateway, NAT Gateway
- Compute: ALB (internet-facing), EC2 Auto Scaling Group with rolling refresh and CPU-based scaling
- Security: security group chain (ALB → EC2), IMDSv2 enforced on instances
- Storage: DynamoDB tables, S3 reports bucket (encryption, versioning, lifecycle), SNS topics
- All Terraform modules (network / compute / iam / data / lambda / dashboard)

**Member C — Hao Ding (Scanner + Dashboard)**
- SAST scanner: Node.js Express server on EC2, 11 vulnerability rule categories (regex-based), Docker image on Docker Hub
- Dashboard API Lambda: reads scan history from DynamoDB, fetches full reports from S3, enforces per-repo isolation
- Frontend dashboard: S3 static website, scan history table, vulnerability report modal
- HIGH vulnerability alerts: SNS vuln-alerts topic → email when HIGH severity issues are detected

---

## Deploy

```bash
# 1. Refresh AWS credentials from Learner Lab → paste into ~/.aws/credentials

# 2. Deploy
cd infra
terraform init
terraform apply

# 3. Update GitHub secret with the new API Gateway URL
gh secret set AWS_LAMBDA_URL \
  --body "$(terraform output -raw lambda_function_url)" \
  --repo ynbonvayage/cs6620_final
```

> **Note:** The API Gateway URL changes on every fresh `terraform apply` from empty state. Always update the `AWS_LAMBDA_URL` secret after redeploying.

---

## Repository Structure

```
cs6620_final/
├── .github/workflows/sast.yml       # A · GitHub Actions SAST pipeline
├── lambda/
│   ├── sast-handler/index.mjs       # A · Lambda orchestrator
│   └── dashboard-api/index.mjs      # C · Dashboard read API
├── frontend/                         # C · Dashboard static website
├── infra/
│   └── modules/
│       ├── network/                  # B · VPC, ALB, subnets, NAT
│       ├── compute/                  # B · EC2 ASG, launch template
│       ├── iam/                      # B · LabInstanceProfile
│       ├── data/                     # A+B · DynamoDB, S3, SNS, CloudWatch
│       ├── lambda/                   # A · Lambda + API Gateway
│       └── dashboard/                # B · Dashboard infra provisioning
└── sast/backend/                     # C · Scanner engine (Node.js + Docker)
```

---

## AWS Academy Notes

- Credentials expire every ~4 hours — re-paste from Learner Lab each session
- `iam:CreateRole` is blocked — all resources use `LabRole` / `LabInstanceProfile`
- `terraform apply -refresh=false` if read APIs are denied mid-session
