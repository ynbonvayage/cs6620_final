# SecureGate — Automated SAST Pipeline on AWS

> CS6620 Cloud Computing · Summer 2026 · Group 03
>
> **Team:** Na Yin (Member A) · Rong Huang (Member B) · Hao Ding (Member C)

An automated Static Application Security Testing (SAST) pipeline that scans every pull request and **blocks merges** if HIGH severity vulnerabilities are found. Scan history is browsable in a live dashboard.

---

## How it works

```
Developer opens PR
       │
       ▼  pull_request trigger
GitHub Actions  (.github/workflows/sast.yml)
       │  differential scan: only JS files changed in this PR
       │  curl POST (jq-built JSON payload)
       ▼
API Gateway v2 (HTTP API)   ← replaces Lambda Function URL (blocked by Learner Lab SCP)
       │
       ▼
AWS Lambda  sast-handler  (Node.js 20)
       │  HTTP POST /scan/code
       ▼
ALB → EC2 Auto Scaling Group  (SAST scanner, private subnets, multi-AZ)
       │
       ▼
Lambda persists results:
       ├──► DynamoDB  securegate-dev-scans     (scan metadata + GSI by repo)
       └──► S3        securegate-dev-reports-* (full JSON reports, Glacier after 30d)
       │
       ├──► SNS vuln-alerts     (when HIGH > 0)
       └──► SNS failure-alerts  (when scanner unreachable or write fails)
       │
       ▼
GitHub Actions posts PR comment with severity table + dashboard link
       ├─ HIGH == 0 → workflow passes → PR can merge
       ├─ HIGH  > 0 → exit 1 → PR merge blocked
       └─ no summary in response → exit 2 → PR blocked (scanner unreachable)

Dashboard (separate read path):
API Gateway v2  ──►  Lambda dashboard-api  ──►  DynamoDB + S3
                                                      │
                                              S3 static frontend
```

---

## Live Resources

| Resource | Value |
|----------|-------|
| Dashboard | `http://securegate-dev-frontend-40157a50.s3-website-us-east-1.amazonaws.com` |
| API Gateway | `https://a6g8qv17gg.execute-api.us-east-1.amazonaws.com` |
| DynamoDB table | `securegate-dev-scans` |
| S3 reports bucket | `securegate-dev-reports-86755d05` |
| ALB | `securegate-dev-alb-190676455.us-east-1.elb.amazonaws.com` |

> Learner Lab credentials expire every ~4 hours. After refreshing credentials and re-running `terraform apply`, the API Gateway URL will change — update the `AWS_LAMBDA_URL` GitHub secret accordingly.

---

## Member A — Na Yin (SAST Pipeline + Data Layer + Alerting)

### 1. Lambda Trigger Layer

**API Gateway v2** (`infra/modules/lambda/`) replaces Lambda Function URL.
Learner Lab SCP blocks `lambda:InvokeFunctionUrl` from outside AWS; API Gateway HTTP API is not subject to this restriction.

**Lambda handler** (`lambda/sast-handler/index.mjs`):
- Receives code scan requests from GitHub Actions via API Gateway
- Calls ALB → EC2 SAST scanner (`POST /scan/code`)
- Writes results to DynamoDB (`scan_id` PK) and S3 (`reports/{repo}/{scanId}.json`)
- Returns `{ scanId, summary, createdAt, dashboardUrl }`

### 2. GitHub Actions SAST Pipeline (`.github/workflows/sast.yml`)
- Triggers on every PR to `main`
- **Differential scan**: only scans JS files added or modified in this PR (`git diff --diff-filter=AM`)
- Uses `jq --arg` for safe JSON encoding (handles quotes, newlines, backslashes in source code)
- Scan result posted as PR comment (severity table + dashboard link)
- `HIGH > 0` → exit 1 → merge blocked
- Scanner unreachable (no `summary` key in response) → exit 2 → merge blocked
- No JS changes → exit 0 → scan skipped

### 3. Data Layer (`infra/modules/data/`)
- DynamoDB `scans` table: `scan_id` PK + GSI `repo-created_at-index` (queries latest scans per repo)
- S3 reports bucket: AES256 encryption, versioning enabled, Glacier after 30 days, auto-delete after 365 days, public access fully blocked

### 4. Monitoring & Alerting
- CloudWatch alarm: `HealthyHostCount < 1` — fires only when **all** EC2 instances are unhealthy; single-instance failure does not trigger
- SNS `failure-alerts` topic → email (infrastructure failure notification)

---

## Member B — Rong Huang (Infrastructure)

| Module | Resources |
|--------|-----------|
| `network` | VPC (10.0.0.0/16), 2 public + 2 private subnets across 2 AZs, IGW, NAT Gateway, ALB (internet-facing, port 80), Target Group (port 3000), security groups |
| `compute` | Launch template (Amazon Linux 2023, IMDSv2 enforced), ASG (desired 2, min 1, max 3, CPU 60% scale-out), rolling instance refresh |
| `iam` | Uses pre-provisioned `LabInstanceProfile` (Academy blocks `iam:CreateRole`) |
| `data` | DynamoDB tables (`scans` + `repos`), S3 reports bucket, SNS `vuln-alerts` + `failure-alerts` |
| `dashboard` | S3 frontend bucket, static website hosting, API Gateway routes for dashboard-api (Terraform provisioning) |

---

## Member C — Hao Ding (Scanner Engine + Dashboard + Alerts)

### 1. SAST Scanner Backend (`sast/backend/`)
- Node.js Express server running on EC2 inside Docker container (`yinnalucky/securegate-sast`)
- `GET /health` — ALB health check endpoint (required for ASG to route traffic)
- `POST /scan/code` — receives code string, runs regex-based SAST analysis, returns results
- **11 vulnerability rule categories**: `HARDCODED_SECRET`, `SQL_INJECTION`, `NOSQL_INJECTION`, `XSS`, `PATH_TRAVERSAL`, `INSECURE_FUNCTION`, `HARDCODED_IP`, `INSECURE_RANDOM`, `SENSITIVE_DATA_LOG`, `WEAK_CRYPTO`, `SECURITY_TODO`
- Results sorted by severity (HIGH → MEDIUM → LOW) then line number
- Docker image: `yinnalucky/securegate-sast:latest` on Docker Hub

### 2. Dashboard Lambda (`lambda/dashboard-api/index.mjs`)
- `GET /api/scans?repo=xxx` — queries DynamoDB via GSI, returns scan list newest-first
- `GET /api/scans/{scanId}` — returns a single scan record
- `GET /api/reports/{scanId}` — fetches the full vulnerability JSON from S3
- Enforces repo isolation: `repo` parameter required on all endpoints (no full-table scans)
- CORS headers on all responses for the S3-hosted frontend

### 3. Frontend Dashboard (`frontend/`)
- S3 static website — shows scan history per repository
- Repo filter via URL parameter (`?repo=org/repo`) — GitHub Actions posts a pre-filtered link in every PR comment
- Report modal: full vulnerability list with type, severity, line number, and evidence

### 4. HIGH Vulnerability Alerts
- SNS `vuln-alerts` topic → email notification when HIGH severity vulnerabilities are detected in a scan

---

## Deploy

### Prerequisites

- AWS Academy Learner Lab (or any AWS account with `LabRole` / `LabInstanceProfile`)
- Terraform ≥ 1.5
- AWS CLI + GitHub CLI (`gh`)

### Steps

```bash
# 1. Clone
git clone https://github.com/ynbonvayage/cs6620_final
cd cs6620_final

# 2. Set AWS credentials (refresh from Learner Lab → AWS Details every ~4 hours)
# Paste credentials into ~/.aws/credentials

# 3. Configure
cd infra
# Edit terraform.tfvars — set alert_email
vi terraform.tfvars

# 4. Deploy everything (network + compute + lambda + dashboard)
terraform init
terraform apply

# 5. Update GitHub secret with the new API Gateway URL
gh secret set AWS_LAMBDA_URL \
  --body "$(terraform output -raw lambda_function_url)" \
  --repo ynbonvayage/cs6620_final

# 6. Confirm SNS subscription email (check inbox)
```

### Verify

```bash
# Hit the Lambda via API Gateway
curl -s -X POST "$(terraform output -raw lambda_function_url)" \
  -H "Content-Type: application/json" \
  -d '{"code":"const p=\"admin123\";","filename":"test.js","repo":"smoke-test"}' \
  | python3 -m json.tool
# Expected: scanId + summary.high >= 1 + dashboardUrl

# Hit the Dashboard API
curl -s "$(terraform output -raw lambda_function_url)api/scans?repo=smoke-test" \
  | python3 -m json.tool
```

### Tear down

```bash
cd infra

# Empty the versioned S3 buckets first
python3 - <<'EOF'
import boto3, subprocess
for key in ["reports_bucket", "frontend_bucket"]:
    bucket = subprocess.check_output(["terraform","output","-raw", key], text=True).strip()
    s3 = boto3.client('s3')
    paginator = s3.get_paginator('list_object_versions')
    for page in paginator.paginate(Bucket=bucket):
        objects = [{'Key': v['Key'], 'VersionId': v['VersionId']}
                   for v in page.get('Versions', []) + page.get('DeleteMarkers', [])]
        if objects:
            s3.delete_objects(Bucket=bucket, Delete={'Objects': objects})
    print(f"Cleared: {bucket}")
EOF

terraform destroy
```

---

## AWS Academy Learner Lab notes

- **AMI hardcoded**: `ami-0521cb2d60cfbb1a6` (AL2023, us-east-1) — `ec2:DescribeImages` and `ssm:GetParameter` are blocked
- **No IAM role creation**: all resources use `LabRole` / `LabInstanceProfile`
- **Credentials expire every ~4 hours**: re-paste from Learner Lab → AWS Details; update `~/.aws/credentials`
- **Lambda Function URL blocked**: SCP denies `lambda:InvokeFunctionUrl` from outside AWS — use API Gateway v2 instead
- **API Gateway URL changes on each fresh deploy**: update the `AWS_LAMBDA_URL` GitHub secret after every `terraform apply` from empty state
- **Save budget**: scale ASG to 0 when not in use: `aws autoscaling update-auto-scaling-group --auto-scaling-group-name securegate-dev-scanner-asg --min-size 0 --desired-capacity 0`

---

## Repository structure

```
cs6620_final/
├── .github/workflows/sast.yml        # A · SAST pipeline (differential scan + PR comment)
├── lambda/
│   ├── sast-handler/index.mjs        # A · Lambda orchestrator (scan + persist + SNS)
│   └── dashboard-api/index.mjs       # A · Dashboard read API (DynamoDB + S3)
├── frontend/
│   ├── index.html                     # A · Dashboard UI
│   ├── style.css                      # A · Dashboard styles
│   └── app.js                         # A · Dashboard logic (API calls + rendering)
├── infra/
│   ├── main.tf                        # Root module wiring
│   ├── terraform.tfvars               # Local config (alert_email, etc.)
│   └── modules/
│       ├── network/                   # B · VPC, ALB, NAT, security groups
│       ├── compute/                   # B · ASG, launch template, user_data
│       ├── iam/                       # B · LabRole / LabInstanceProfile
│       ├── data/                      # A+B · DynamoDB, S3, SNS, CloudWatch alarm
│       ├── lambda/                    # A · sast-handler Lambda + API Gateway v2
│       └── dashboard/                 # A · dashboard-api Lambda + routes + S3 frontend
└── sast/backend/                      # C · SAST scanner (Node.js, Docker: yinnalucky/securegate-sast)
    ├── server.js                       # C · Express server + endpoints
    ├── scanner.js                      # C · 11-rule regex SAST engine
    └── Dockerfile                      # C · Container image definition
```
