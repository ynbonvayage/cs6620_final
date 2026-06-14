variable "name" {
  description = "Resource name prefix"
  type        = string
}

variable "dynamodb_table" {
  description = "Name of the scans DynamoDB table"
  type        = string
}

variable "s3_bucket" {
  description = "Name of the reports S3 bucket"
  type        = string
}

variable "account_id" {
  description = "AWS account ID — used to build the LabRole ARN"
  type        = string
}

variable "api_id" {
  description = "API Gateway v2 API ID — shared with the SAST handler"
  type        = string
}

variable "api_execution_arn" {
  description = "API Gateway v2 execution ARN — used for Lambda permission"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name for frontend website hosting"
  type        = string
}
