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

resource "aws_sns_topic_subscription" "failure_email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.failure_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

###############################################################################
# CloudWatch alarm: fires when any EC2 target is unhealthy in the ALB TG
###############################################################################

locals {
  # CloudWatch dimensions use the suffix of the ARN after the last colon.
  tg_dimension  = element(split(":", var.target_group_arn), length(split(":", var.target_group_arn)) - 1)
  alb_dimension = replace(element(split(":", var.alb_arn), length(split(":", var.alb_arn)) - 1), "loadbalancer/", "")
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.name}-unhealthy-hosts"
  alarm_description   = "All SAST scanner EC2 targets are unhealthy — service is completely down."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    TargetGroup  = local.tg_dimension
    LoadBalancer = local.alb_dimension
  }

  alarm_actions = [aws_sns_topic.failure_alerts.arn]
  ok_actions    = [aws_sns_topic.failure_alerts.arn]

  tags = { Name = "${var.name}-unhealthy-hosts" }
}

###############################################################################
# CloudWatch alarm: fires when the SAST Lambda function errors
###############################################################################

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name}-lambda-errors"
  alarm_description   = "SAST Lambda function is throwing errors — scans may be failing."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = [aws_sns_topic.failure_alerts.arn]
  ok_actions    = [aws_sns_topic.failure_alerts.arn]

  tags = { Name = "${var.name}-lambda-errors" }
}

###############################################################################
# CloudWatch Dashboard: SecureGate operational overview
###############################################################################

resource "aws_cloudwatch_dashboard" "securegate" {
  dashboard_name = "${var.name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# SecureGate — Operational Dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Invocations"
          region = "us-east-1"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_name, { stat = "Sum", period = 300 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = "us-east-1"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_name, { stat = "Sum", period = 300, color = "#d62728" }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Duration (ms)"
          region = "us-east-1"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "Average", period = 300 }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "p99", period = 300, color = "#ff7f0e" }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "ALB Healthy Host Count"
          region = "us-east-1"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.tg_dimension, "LoadBalancer", local.alb_dimension, { stat = "Minimum", period = 60 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          region = "us-east-1"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_dimension, { stat = "Sum", period = 300 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB Scans — Consumed Read/Write"
          region = "us-east-1"
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.scans.name, { stat = "Sum", period = 300 }],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.scans.name, { stat = "Sum", period = 300, color = "#ff7f0e" }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "S3 Reports — Total Requests"
          region = "us-east-1"
          metrics = [
            ["AWS/S3", "AllRequests", "BucketName", aws_s3_bucket.reports.bucket, "FilterId", "EntireBucket", { stat = "Sum", period = 300 }]
          ]
          view = "timeSeries"
        }
      }
    ]
  })
}
