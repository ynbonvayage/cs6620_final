variable "name" {
  description = "Name prefix for all resources (e.g. securegate-dev)"
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "app_port" {
  description = "Port the scanner service listens on (ALB -> instances)"
  type        = number
}
