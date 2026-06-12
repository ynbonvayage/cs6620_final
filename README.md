# SecureGate · Cloud Security Platform

> CS6620 Cloud Computing · Spring 2026 Final Project
> An automated SAST (Static Application Security Testing) pipeline deployed on AWS that scans every pull request and blocks merges containing HIGH severity vulnerabilities.

---

## What this project does

When a developer opens a pull request, the source code is automatically scanned for security vulnerabilities such as hardcoded secrets, SQL injection patterns, weak cryptography, and insecure functions. If any HIGH severity issues are detected, the workflow fails and the PR cannot be merged into `main`. Scan history and full reports are persisted for later review and monitoring.

Security becomes a **continuous, automatic check** built into the development workflow — not a manual review step that gets skipped under deadline pressure.

---

## Architecture

```
Developer opens PR
        │
        ▼   pull_request trigger
GitHub Actions  (.github/workflows/sast.yml)
        │
        │   curl POST (jq-built JSON payload)
        ▼
API Gateway v2 (HTTP API)
        │
        ▼
AWS Lambda · securegate-dev-sast-handler
        │
        │   HTTP POST /scan/code
        ▼
Application Load Balancer
        │
        ▼
Auto Scaling Group · EC2 SAST Scanner (private subnets, multi-AZ)
        │
        │   scan results
        ▼
Lambda persists in parallel:
        ├──► DynamoDB · securegate-dev-scans       (metadata, fast queries)
        └──► S3       · securegate-dev-reports-*   (full JSON reports)
        │
        │   returns summary
        ▼
GitHub Actions checks summary.high
        ├─ high == 0 → workflow passes → PR can merge
        └─ high  > 0 → workflow fails  → PR merge blocked by branch protection
```

---

## Team & responsibilities

| Member | Owns | Key components |
|--------|------|----------------|
| **A — Na Yin** | SAST automation pipeline | Lambda orchestrator, GitHub Actions workflow, API Gateway integration |
| **B — Rong Huang** | Infrastructure & IaC | VPC, ALB, ASG, IAM roles, all Terraform main structure |
| **C — TBD** | Data layer + Portal + Monitoring | DynamoDB/S3 schema, Portal frontend/backend, CloudWatch + SNS alerts |

---

## Repository structure

```
cs6620_final/
├── .github/
│   └── workflows/
│       └── sast.yml              # GitHub Actions: triggers scan on every PR
├── infra/                        # Terraform Infrastructure as Code
│   ├── main.tf                   # Root module wiring
│   ├── outputs.tf                # Exposes ALB DNS, table names, Lambda URL, etc.
│   ├── variables.tf
│   ├── versions.tf
│   ├── terraform.tfvars          # (gitignored) Local overrides
│   ├── terraform.tfvars.example  # Template for new contributors
│   └── modules/
│       ├── network/              # B · VPC, subnets, ALB, NAT, security groups
│       ├── compute/              # B · Launch template, ASG running SAST scanner
│       ├── data/                 # B · DynamoDB tables, S3 bucket, SNS topics
│       ├── iam/                  # B · IAM helpers (uses LabRole in Academy)
│       └── lambda/               # A · Lambda function + API Gateway v2
├── lambda/
│   └── sast-handler/
│       └── index.mjs             # A · Lambda source — orchestrates scan & persistence
├── sast/
│   └── backend/                  # SAST scanner (Node.js Express + regex rules)
│       ├── server.js
│       ├── scanner.js
│       └── package.json
├── HANDOFF_TO_C.md               # Handoff doc explaining DynamoDB schema, S3 keys, etc.
└── README.md                     # This file
```

---

## Deployment (clean account)

### Prerequisites

- AWS Academy Learner Lab access (or any AWS account where `LabRole` exists)
- Terraform ≥ 1.5
- AWS CLI configured with valid credentials

### One-command deploy

```bash
# 1. Set AWS credentials (from Learner Lab → AWS Details → AWS CLI)
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# 2. Deploy all infrastructure
cd infra
terraform init
terraform apply

# 3. Get the API Gateway URL
terraform output lambda_function_url

# 4. Set the GitHub secret
gh secret set AWS_LAMBDA_URL \
  --body "$(terraform output -raw lambda_function_url)" \
  --repo <your-fork>
```

### Verify

```bash
URL=$(terraform output -raw lambda_function_url)
curl -s -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{"code": "const password = \"admin123\";", "filename": "test.js", "repo": "smoke-test"}' \
  | python3 -m json.tool
```

Expected: response includes a `scanId` and `summary.high >= 1`.

---

## How to test the merge gate

```bash
git checkout -b test-vuln
echo 'const password = "admin123";' > vuln.js
git add vuln.js
git commit -m "test: try to merge vulnerable code"
git push origin test-vuln
```

Open a PR for `test-vuln` → `main`. The SAST workflow runs automatically. Because the file contains a HIGH severity finding, the workflow fails and the **Merge** button is disabled by branch protection.

---

## Tech stack

- **IaC**: Terraform 1.5+
- **Compute**: AWS Lambda (Node.js 20), EC2 ASG behind ALB
- **API**: API Gateway v2 (HTTP API)
- **Storage**: DynamoDB (scan metadata), S3 (full reports)
- **Notifications**: SNS topics (provisioned, integration in progress — see HANDOFF_TO_C.md)
- **CI**: GitHub Actions, `jq` for safe JSON construction
- **Auth**: AWS Academy `LabRole` (IAM creation blocked in Academy environment)

---

## Vulnerability types detected

The SAST scanner uses regex pattern matching to detect 10 categories:

- Hardcoded secrets (API keys, passwords, tokens)
- SQL injection patterns
- NoSQL injection patterns
- Cross-site scripting (XSS)
- Path traversal
- Insecure functions (`eval`, `exec`)
- Hardcoded IP addresses
- Weak randomness (`Math.random()` for security)
- Sensitive data in logs
- Weak cryptography (MD5, SHA1)

---

## What's done vs what's planned

| Area | Status |
|------|--------|
| Containerized SAST scanner | ✅ Running on EC2 ASG in private subnets |
| ALB in front of scanner | ✅ Multi-AZ, internet-facing |
| Lambda orchestrator | ✅ Terraform-managed, API Gateway frontend |
| DynamoDB persistence | ✅ Metadata writes, `scan_id` partition key |
| S3 persistence | ✅ Full JSON reports, key format `reports/{repo}/{scan_id}.json` |
| GitHub Actions workflow | ✅ jq-built payload, fail-loud error handling |
| Branch protection rule | ✅ `sast-scan` required for `main` |
| SNS publish on HIGH | 🟡 Topic provisioned, Lambda integration pending (see HANDOFF_TO_C.md) |
| Portal (scan history + detail) | 🟡 Member C scope |
| CloudWatch dashboard | 🟡 Member C scope |
| GitHub OIDC for AWS auth | ⏳ Blocked by Academy IAM restrictions |
| PR comment with vuln details | ⏳ M2 stretch goal |

---

## Known limitations

- **AWS Academy IAM**: `iam:CreateRole` is blocked, so all components use the shared `LabRole`. In a production deployment we would create least-privilege roles per component.
- **AWS Academy SCP on Lambda Function URLs**: External calls to Function URLs get 403 even with public auth. We use API Gateway v2 instead — this is the recommended path anyway for production.
- **`repo` field defaults to `"unknown"`**: The GitHub Actions workflow doesn't yet pass `github.repository` to the Lambda. Easy fix in `sast.yml`.

---

## References

- Member C handoff guide: [`HANDOFF_TO_C.md`](./HANDOFF_TO_C.md)
- Lambda source: [`lambda/sast-handler/index.mjs`](./lambda/sast-handler/index.mjs)
- Workflow: [`.github/workflows/sast.yml`](./.github/workflows/sast.yml)
- Terraform outputs (live values): `cd infra && terraform output`

---

## Credits

- **Original SAST scanner**: forked from `aanchan/cs6620` (course material)
- **Cloud architecture**: Members A, B, C of Team SecureGate, Spring 2026