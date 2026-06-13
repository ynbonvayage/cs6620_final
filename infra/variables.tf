variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a name prefix on all resources"
  type        = string
  default     = "securegate"
}

variable "env" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the public subnets (ALB, NAT)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the private subnets (scanner EC2 / ASG)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI for us-east-1. Learner Lab blocks both ssm:GetParameter and ec2:DescribeImages so this must be hardcoded. Find a fresh ID at: https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#AMICatalog"
  type        = string
  default     = "ami-0521cb2d60cfbb1a6"
}

variable "instance_type" {
  description = "EC2 instance type for the scanner fleet"
  type        = string
  default     = "t3.micro"
}

variable "asg_desired" {
  description = "Desired number of scanner instances"
  type        = number
  default     = 2
}

variable "asg_min" {
  description = "Minimum scanner instances"
  type        = number
  default     = 1
}

variable "asg_max" {
  description = "Maximum scanner instances"
  type        = number
  default     = 3
}

variable "app_port" {
  description = "Port the scanner service listens on inside each instance"
  type        = number
  default     = 3000
}

variable "repo_url" {
  description = "Git URL the scanner instances clone to run the SAST backend"
  type        = string
  default     = "https://github.com/ynbonvayage/cs6620_final.git"
}

variable "github_repo" {
  description = "GitHub org/repo allowed to assume the CI role via OIDC"
  type        = string
  default     = "secure-gate-org/securegate"
}

variable "alert_email" {
  description = "Email to subscribe to the HIGH-severity SNS topic (optional; leave blank to skip)"
  type        = string
  default     = ""
}

variable "create_iam" {
  description = <<-EOT
    Whether Terraform should create its own IAM roles + GitHub OIDC provider.
    AWS Academy / Voclabs lab accounts deny iam:CreateRole, so this defaults to
    false and the stack uses the pre-provisioned LabRole / LabInstanceProfile.
    Set true in a full account to provision least-privilege roles from iam_github_oidc.tf.
  EOT
  type        = bool
  default     = false
}

variable "lab_instance_profile" {
  description = "Pre-provisioned instance profile to attach to EC2 when create_iam = false"
  type        = string
  default     = "LabInstanceProfile"
}
