variable "name" {
  type = string
}

variable "create_iam" {
  description = "Create custom IAM roles + OIDC provider (false in Learner Lab)"
  type        = bool
}

variable "lab_instance_profile" {
  description = "Pre-provisioned instance profile to use when create_iam = false"
  type        = string
}

variable "partition" {
  type = string
}

variable "github_repo" {
  type = string
}

# ARNs the (optional) least-privilege instance role is scoped to.
variable "reports_bucket_arn" {
  type = string
}

variable "scans_table_arn" {
  type = string
}

variable "repos_table_arn" {
  type = string
}

variable "vuln_topic_arn" {
  type = string
}

variable "failure_topic_arn" {
  type = string
}
