output "lambda_function_url" {
  description = "Set this as the AWS_LAMBDA_URL secret in GitHub repository settings"
  value       = module.lambda.function_url
}

output "lambda_function_arn" {
  value = module.lambda.function_arn
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "alb_dns_name" {
  description = "Public DNS of the ALB — curl this to hit the scanner fleet"
  value       = module.network.alb_dns_name
}

output "asg_name" {
  value = module.compute.asg_name
}

output "instance_profile_used" {
  value = module.iam.instance_profile_arn
}

output "github_ci_role_arn" {
  value = module.iam.github_ci_role_arn
}

output "reports_bucket" {
  value = module.data.reports_bucket
}

output "scans_table" {
  value = module.data.scans_table
}

output "repos_table" {
  value = module.data.repos_table
}

output "vuln_alerts_topic_arn" {
  value = module.data.vuln_alerts_topic_arn
}

output "failure_alerts_topic_arn" {
  value = module.data.failure_alerts_topic_arn
}

output "dashboard_url" {
  description = "Frontend dashboard URL — open in browser to view scan logs"
  value       = "http://${module.dashboard.frontend_website_url}"
}

output "dashboard_api_url" {
  description = "Dashboard API base URL (same API Gateway as SAST handler)"
  value       = module.lambda.function_url
}

output "frontend_bucket" {
  description = "S3 bucket to upload frontend files to"
  value       = module.dashboard.frontend_bucket
}
