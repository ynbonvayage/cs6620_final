###############################################################################
# NOTE: Rong (infra/IaC) provisions these resources. Teammate Na Yin owns the
# *design* on top — table schema, S3 path conventions, alert rules, the portal,
# and CloudWatch. This module is the provisioning boundary between them.
###############################################################################

###############################################################################
# S3 bucket: long-term archive for full JSON scan reports
###############################################################################

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "reports" {
  bucket = "${var.name}-reports-${random_id.bucket_suffix.hex}"
  tags   = { Name = "${var.name}-reports" }
}

resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "archive-old-reports"
    status = "Enabled"
    filter {}

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

###############################################################################
# DynamoDB: scan metadata + repo registry
###############################################################################

resource "aws_dynamodb_table" "scans" {
  name         = "${var.name}-scans"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "scan_id"

  attribute {
    name = "scan_id"
    type = "S"
  }
  attribute {
    name = "repo"
    type = "S"
  }
  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "repo-created_at-index"
    hash_key        = "repo"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "${var.name}-scans" }
}

resource "aws_dynamodb_table" "repos" {
  name         = "${var.name}-repos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "repo_id"

  attribute {
    name = "repo_id"
    type = "S"
  }

  tags = { Name = "${var.name}-repos" }
}

###############################################################################
# SNS: HIGH-severity vulnerability alerts + scan-failure notifications
###############################################################################

resource "aws_sns_topic" "vuln_alerts" {
  name = "${var.name}-vuln-alerts"
  tags = { Name = "${var.name}-vuln-alerts" }
}

resource "aws_sns_topic" "failure_alerts" {
  name = "${var.name}-failure-alerts"
  tags = { Name = "${var.name}-failure-alerts" }
}

resource "aws_sns_topic_subscription" "vuln_email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.vuln_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
