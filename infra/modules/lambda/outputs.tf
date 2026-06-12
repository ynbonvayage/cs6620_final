output "function_url" {
  description = "API Gateway invoke URL — set this as the AWS_LAMBDA_URL GitHub secret"
  value       = aws_apigatewayv2_stage.sast.invoke_url
}

output "function_arn" {
  value = aws_lambda_function.sast_handler.arn
}
