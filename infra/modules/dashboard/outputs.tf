output "frontend_bucket" {
  description = "S3 bucket name for the dashboard frontend"
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_website_url" {
  description = "S3 static website endpoint — open this URL in a browser"
  value       = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

output "dashboard_api_function_name" {
  value = aws_lambda_function.dashboard_api.function_name
}
