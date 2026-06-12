variable "name" {
  description = "Resource name prefix (matches the other modules)"
  type        = string
}

variable "sast_url" {
  description = "ALB DNS name — Lambda calls http://<sast_url>/scan/code"
  type        = string
}

variable "dynamodb_table" {
  description = "Name of Member B's scans DynamoDB table"
  type        = string
}

variable "s3_bucket" {
  description = "Name of Member B's reports S3 bucket"
  type        = string
}

variable "account_id" {
  description = "AWS account ID — used to build the LabRole ARN"
  type        = string
}
