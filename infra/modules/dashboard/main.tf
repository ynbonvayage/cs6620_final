###############################################################################
# SecureGate Dashboard — Lambda + API Gateway routes + S3 static hosting
###############################################################################

# --- Dashboard API Lambda ---------------------------------------------------

data "archive_file" "dashboard" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/dashboard-api"
  output_path = "${path.root}/../lambda/dashboard-api.zip"
}

resource "aws_lambda_function" "dashboard_api" {
  function_name    = "${var.name}-dashboard-api"
  role             = "arn:aws:iam::${var.account_id}:role/LabRole"
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.dashboard.output_path
  source_code_hash = data.archive_file.dashboard.output_base64sha256
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table
      S3_BUCKET      = var.s3_bucket
      VULN_TOPIC_ARN = var.vuln_topic_arn
    }
  }

  tags = { Name = "${var.name}-dashboard-api" }
}

# --- API Gateway routes (added to the shared SAST API Gateway) ---------------

resource "aws_apigatewayv2_integration" "dashboard" {
  api_id                 = var.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dashboard_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "list_scans" {
  api_id    = var.api_id
  route_key = "GET /api/scans"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard.id}"
}

resource "aws_apigatewayv2_route" "get_scan" {
  api_id    = var.api_id
  route_key = "GET /api/scans/{scanId}"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard.id}"
}

resource "aws_apigatewayv2_route" "get_report" {
  api_id    = var.api_id
  route_key = "GET /api/reports/{scanId}"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard.id}"
}

resource "aws_apigatewayv2_route" "subscribe" {
  api_id    = var.api_id
  route_key = "POST /api/subscribe"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard.id}"
}

resource "aws_apigatewayv2_route" "cors_subscribe" {
  api_id    = var.api_id
  route_key = "OPTIONS /api/subscribe"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard.id}"
}

resource "aws_lambda_permission" "dashboard_apigw" {
  statement_id  = "AllowAPIGatewayInvokeDashboard"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dashboard_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_execution_arn}/*/*"
}

# --- CORS configuration for the shared API Gateway --------------------------

resource "aws_apigatewayv2_route" "cors_scans" {
  api_id    = var.api_id
  route_key = "OPTIONS /api/scans"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard.id}"
}

resource "aws_apigatewayv2_route" "cors_scan_detail" {
  api_id    = var.api_id
  route_key = "OPTIONS /api/scans/{scanId}"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard.id}"
}

resource "aws_apigatewayv2_route" "cors_reports" {
  api_id    = var.api_id
  route_key = "OPTIONS /api/reports/{scanId}"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard.id}"
}

resource "aws_s3_bucket" "frontend" {
  bucket = var.bucket_name
  tags   = { Name = "${var.name}-frontend" }
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "${path.root}/../frontend/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.root}/../frontend/index.html")
}

resource "aws_s3_object" "style" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "style.css"
  source       = "${path.root}/../frontend/style.css"
  content_type = "text/css"
  etag         = filemd5("${path.root}/../frontend/style.css")
}

resource "aws_s3_object" "app" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "app.js"
  content      = replace(
    file("${path.root}/../frontend/app.js"),
    "/const API_BASE_URL = \".*\";/",
    "const API_BASE_URL = \"https://${var.api_id}.execute-api.us-east-1.amazonaws.com\";"
  )
  content_type = "application/javascript"
  etag         = md5(replace(
    file("${path.root}/../frontend/app.js"),
    "/const API_BASE_URL = \".*\";/",
    "const API_BASE_URL = \"https://${var.api_id}.execute-api.us-east-1.amazonaws.com\";"
  ))
}
