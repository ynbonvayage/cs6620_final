# Zip the handler source from lambda/sast-handler/ at the project root.
# path.root is infra/, so ../lambda/sast-handler resolves correctly.
data "archive_file" "handler" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/sast-handler"
  output_path = "${path.root}/../lambda/sast-handler.zip"
}

resource "aws_lambda_function" "sast_handler" {
  function_name    = "${var.name}-sast-handler"
  role             = "arn:aws:iam::${var.account_id}:role/LabRole"
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      SAST_URL          = "http://${var.sast_url}"
      DYNAMODB_TABLE    = var.dynamodb_table
      S3_BUCKET         = var.s3_bucket
      VULN_TOPIC_ARN    = var.vuln_topic_arn
      FAILURE_TOPIC_ARN = var.failure_topic_arn
      DASHBOARD_URL     = "http://securegate-dev-frontend-1ee45719.s3-website-us-east-1.amazonaws.com"
    }
  }

  tags = { Name = "${var.name}-sast-handler" }
}

# API Gateway v2 (HTTP API) replaces Lambda Function URL.
# Learner Lab SCPs block lambda:InvokeFunctionUrl from outside AWS networks;
# API Gateway is not subject to that restriction.
resource "aws_apigatewayv2_api" "sast" {
  name          = "${var.name}-sast-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "sast" {
  api_id                 = aws_apigatewayv2_api.sast.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.sast_handler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "sast" {
  api_id    = aws_apigatewayv2_api.sast.id
  route_key = "POST /"

  target = "integrations/${aws_apigatewayv2_integration.sast.id}"
}

resource "aws_apigatewayv2_stage" "sast" {
  api_id      = aws_apigatewayv2_api.sast.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sast_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.sast.execution_arn}/*/*"
}
