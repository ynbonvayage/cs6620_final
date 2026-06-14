variable "name" {
  type = string
}

variable "alert_email" {
  description = "Email subscribed to both alert SNS topics (blank to skip)"
  type        = string
  default     = ""
}

variable "target_group_arn" {
  description = "ARN of the ALB target group — used for UnHealthyHostCount alarm"
  type        = string
}

variable "alb_arn" {
  description = "ARN of the Application Load Balancer — used for UnHealthyHostCount alarm"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the SAST Lambda function — used for CloudWatch error alarm"
  type        = string
}

