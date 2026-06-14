# SecureGate — Automated SAST Pipeline on AWS

> CS6620 Cloud Computing · Summer 2026 · Group 03

An automated Static Application Security Testing (SAST) pipeline that scans every pull request and **blocks merges** if HIGH severity vulnerabilities are found.

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
API Gateway v2 (HTTP API)
       │
       ▼
AWS Lambda  (Node.js 20)
       │  HTTP POST /scan/code
       ▼
ALB → EC2 Auto Scaling Group  (SAST scanner, private subnets, multi-AZ)
       │
       ▼
Lambda writes results:
       ├──► DynamoDB  securegate-dev-scans     (scan metadata, queryable by repo)
       └──► S3        securegate-dev-reports-* (full JSON reports)
       │
       ▼
GitHub Actions posts PR comment with severity table
       ├─ HIGH == 0 → workflow passes → PR can merge
       └─ HIGH  > 0 → workflow fails  → PR merge blocked
```

---

## Member A — Na Yin (SAST Pipeline)

### Lambda Orchestrator (`lambda/sast-handler/index.mjs`)
- Receives scan requests from GitHub Actions via API Gateway
- Forwards code to the SAST scanner running on EC2 behind ALB
- Persists results: DynamoDB (`scan_id` PK) + S3 (`reports/{repo}/{scanId}.json`)
- Returns `{ scanId, createdAt, summary: { high, medium, low, totalVulnerabilities } }`

### API Gateway v2 (`infra/modules/lambda/`)
- HTTP API fronting the Lambda function
- Replaces Lambda Function URL (AWS Academy SCP blocks `lambda:InvokeFunctionUrl` from outside AWS networks)

### GitHub Actions Workflow (`.github/workflows/sast.yml`)
- Triggers on every PR to `main`
- **Differential scan**: only scans JS files added or modified in the PR (`git diff --diff-filter=AM`)
- Posts scan results as a PR comment (severity table + scan ID)
- Exits 1 (blocks merge) if `HIGH > 0`
- Exits 2 (blocks merge) if scanner is unreachable
- Exits 0 (passes) if no HIGH findings or no JS changes

### Data Design (`infra/modules/data/`)
- DynamoDB `scans` table: `scan_id` partition key + GSI `repo-created_at-index` for querying latest scans per repo
- S3 reports bucket: AES256 encryption, versioning enabled, Glacier transition after 30 days, auto-delete after 365 days

### CloudWatch Alarm (`infra/modules/data/`)
- Monitors `HealthyHostCount < 1` — fires only when **all** EC2 instances are unhealthy (service completely down)
- Triggers SNS `failure-alerts` topic → email notification


---

## Frontend Dashboard

A premium, glassmorphism dark-themed dashboard is hosted on S3 to visualize scan history.

- **Dashboard URL**: [http://securegate-dev-frontend-1ee45719.s3-website-us-east-1.amazonaws.com](http://securegate-dev-frontend-1ee45719.s3-website-us-east-1.amazonaws.com)
- **Data Privacy & Isolation (Option A)**:
  - The dashboard enforces isolation and requires a `repo` parameter in the URL (e.g., `?repo=your-org/your-repo`) or typing the repository in the search box to view logs.
  - Direct full table scans of the database are blocked at the Lambda API level to protect repository data privacy (returning `400 Bad Request` if the `repo` parameter is missing).
- **PR Direct Link**:
  - GitHub Actions dynamically posts a direct, pre-filtered link on each PR page, allowing developers to review their full report history in one click.

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
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# 3. Configure
cd infra
# Edit terraform.tfvars — set your alert_email
vi terraform.tfvars

# 4. Deploy
terraform init
terraform apply

# 5. Set GitHub secret for the workflow
gh secret set AWS_LAMBDA_URL \
  --body "$(terraform output -raw lambda_function_url)" \
  --repo <your-fork>

# 6. Confirm SNS subscription email (check inbox for "AWS Notification - Subscription Confirmation")
```

### Verify

```bash
# Hit the Lambda directly
curl -s -X POST "$(terraform output -raw lambda_function_url)" \
  -H "Content-Type: application/json" \
  -d '{"code":"const p=\"admin123\";","filename":"test.js","repo":"smoke-test"}' \
  | python3 -m json.tool
# Expected: scanId + summary.high >= 1
```

### Tear down

```bash
# Empty the versioned S3 bucket first (replace bucket name from terraform output)
~/miniconda3/bin/python3 - <<'EOF'
import boto3, subprocess
bucket = subprocess.check_output(
    ["terraform","output","-raw","reports_bucket"], text=True).strip()
s3 = boto3.client('s3')
paginator = s3.get_paginator('list_object_versions')
for page in paginator.paginate(Bucket=bucket):
    objects = [{'Key': v['Key'], 'VersionId': v['VersionId']}
               for v in page.get('Versions', []) + page.get('DeleteMarkers', [])]
    if objects:
        s3.delete_objects(Bucket=bucket, Delete={'Objects': objects})
print("Bucket cleared")
EOF

terraform destroy
```

---

## Test the merge gate

```bash
# Should be BLOCKED (HIGH vulnerabilities)
git checkout -b test/blocked
echo 'const secret = "hardcoded_password_123"; eval(userInput);' > test.js
git add test.js && git commit -m "test: vulnerable code"
git push origin test/blocked
gh pr create --title "Test blocked" --base main

# Should PASS (clean code)
git checkout -b test/clean
echo 'console.log("hello world");' > test.js
git add test.js && git commit -m "test: clean code"
git push origin test/clean
gh pr create --title "Test clean" --base main
```

---

## Infrastructure overview (Member B — Rong Huang)

| Module | Resources |
|--------|-----------|
| `network` | VPC (10.0.0.0/16), 2 public + 2 private subnets across 2 AZs, IGW, single NAT Gateway, ALB (internet-facing, port 80), Target Group (port 3000), security groups |
| `compute` | Launch template (Amazon Linux 2023, IMDSv2), Auto Scaling Group (desired 2, min 1, max 3), rolling instance refresh |
| `iam` | Uses pre-provisioned `LabInstanceProfile` (Academy blocks `iam:CreateRole`) |
| `data` | DynamoDB tables (`scans`, `repos`), S3 reports bucket, SNS `vuln-alerts` + `failure-alerts` topics |

---

## AWS Academy Learner Lab notes

- **AMI hardcoded**: `ami-0521cb2d60cfbb1a6` (AL2023, us-east-1) — `ec2:DescribeImages` and `ssm:GetParameter` are blocked
- **No IAM role creation**: all resources use `LabRole` / `LabInstanceProfile`
- **Credentials expire every ~4 hours**: re-export from Learner Lab → AWS Details; `voc-cancel-cred` explicit deny means credentials are revoked
- **Terraform refresh blocked**: use `terraform apply -refresh=false` when read APIs are denied
- **Lambda Function URL blocked**: SCP denies `lambda:InvokeFunctionUrl` from outside AWS; use API Gateway v2 instead

---

## Repository structure

```
cs6620_final/
├── .github/workflows/sast.yml     # A · SAST pipeline (differential scan + PR comment)
├── lambda/sast-handler/index.mjs  # A · Lambda orchestrator
├── infra/
│   ├── main.tf                    # Root module wiring
│   ├── terraform.tfvars           # Local config (alert_email, etc.)
│   └── modules/
│       ├── network/               # B · VPC, ALB, NAT, security groups
│       ├── compute/               # B · ASG, launch template, user_data
│       ├── iam/                   # B · LabRole / LabInstanceProfile
│       ├── data/                  # A+B · DynamoDB, S3, SNS, CloudWatch alarm
│       └── lambda/                # A · Lambda + API Gateway v2
├── sast/backend/                  # SAST scanner (Node.js, Docker image: yinnalucky/securegate-sast)
└── infra/study/architecture-review.html  # Study guide for mock interview
```
