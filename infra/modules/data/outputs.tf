output "reports_bucket" {
  value = aws_s3_bucket.reports.bucket
}

output "reports_bucket_arn" {
  value = aws_s3_bucket.reports.arn
}

output "scans_table" {
  value = aws_dynamodb_table.scans.name
}

output "scans_table_arn" {
  value = aws_dynamodb_table.scans.arn
}

output "repos_table" {
  value = aws_dynamodb_table.repos.name
}

output "repos_table_arn" {
  value = aws_dynamodb_table.repos.arn
}

output "vuln_alerts_topic_arn" {
  value = aws_sns_topic.vuln_alerts.arn
}

output "failure_alerts_topic_arn" {
  value = aws_sns_topic.failure_alerts.arn
}
