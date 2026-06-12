###############################################################################
# EC2 identity
#
# AWS Academy / Voclabs lab accounts deny iam:CreateRole, so by default we
# attach the pre-provisioned LabInstanceProfile (which wraps LabRole and already
# carries S3 / DynamoDB / SNS / SSM permissions). In a full account, set
# create_iam = true to provision the least-privilege role + GitHub OIDC instead.
###############################################################################

data "aws_iam_instance_profile" "lab" {
  count = var.create_iam ? 0 : 1
  name  = var.lab_instance_profile
}

# ---------- EC2 instance role (only when create_iam = true) ----------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  count              = var.create_iam ? 1 : 0
  name               = "${var.name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "instance_perms" {
  statement {
    sid       = "ReportsBucket"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [var.reports_bucket_arn, "${var.reports_bucket_arn}/*"]
  }
  statement {
    sid       = "Dynamo"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:Query", "dynamodb:Scan"]
    resources = [var.scans_table_arn, "${var.scans_table_arn}/index/*", var.repos_table_arn]
  }
  statement {
    sid       = "Sns"
    actions   = ["sns:Publish"]
    resources = [var.vuln_topic_arn, var.failure_topic_arn]
  }
}

resource "aws_iam_role_policy" "instance" {
  count  = var.create_iam ? 1 : 0
  name   = "${var.name}-instance-policy"
  role   = aws_iam_role.instance[0].id
  policy = data.aws_iam_policy_document.instance_perms.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count      = var.create_iam ? 1 : 0
  role       = aws_iam_role.instance[0].name
  policy_arn = "arn:${var.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  count = var.create_iam ? 1 : 0
  name  = "${var.name}-instance-profile"
  role  = aws_iam_role.instance[0].name
}

# ---------- GitHub Actions OIDC provider + keyless CI role ----------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_iam ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fce",
  ]
}

data "aws_iam_policy_document" "github_assume" {
  count = var.create_iam ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_ci" {
  count              = var.create_iam ? 1 : 0
  name               = "${var.name}-github-ci-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json
}

data "aws_iam_policy_document" "github_ci_perms" {
  statement {
    sid       = "PutReports"
    actions   = ["s3:PutObject"]
    resources = ["${var.reports_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "github_ci" {
  count  = var.create_iam ? 1 : 0
  name   = "${var.name}-github-ci-policy"
  role   = aws_iam_role.github_ci[0].id
  policy = data.aws_iam_policy_document.github_ci_perms.json
}

locals {
  instance_profile_arn = var.create_iam ? aws_iam_instance_profile.instance[0].arn : data.aws_iam_instance_profile.lab[0].arn
}
