output "function_url" {
  description = "API Gateway invoke URL — set this as the AWS_LAMBDA_URL GitHub secret"
  value       = aws_apigatewayv2_stage.sast.invoke_url
}

output "function_arn" {
  value = aws_lambda_function.sast_handler.arn
}

output "function_name" {
  description = "Lambda function name — used for CloudWatch alarm dimensions"
  value       = aws_lambda_function.sast_handler.function_name
}

output "api_id" {
  description = "API Gateway v2 API ID — shared with dashboard module"
  value       = aws_apigatewayv2_api.sast.id
}

output "api_execution_arn" {
  description = "API Gateway execution ARN — used for Lambda permission source_arn"
  value       = aws_apigatewayv2_api.sast.execution_arn
}
