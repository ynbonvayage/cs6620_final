variable "name" {
  type = string
}

variable "env" {
  type = string
}

variable "ami_id" {
  description = "AMI for the scanner fleet (Amazon Linux 2023)"
  type        = string
}

variable "instance_type" {
  type = string
}

variable "asg_desired" {
  type = number
}

variable "asg_min" {
  type = number
}

variable "asg_max" {
  type = number
}

variable "app_port" {
  type = number
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "instance_sg_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "instance_profile_arn" {
  description = "Instance profile to attach (LabInstanceProfile in lab, custom in full account)"
  type        = string
}
