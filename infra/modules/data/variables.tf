variable "name" {
  type = string
}

variable "alert_email" {
  description = "Email subscribed to the HIGH-severity SNS topic (blank to skip)"
  type        = string
  default     = ""
}
