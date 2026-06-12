###############################################################################
# SecureGate — root module. Wires the four sub-modules together.
#
#   data    -> S3 / DynamoDB / SNS        (provisioned by Rong, designed by Na Yin)
#   network -> VPC / subnets / NAT / ALB  (Rong)
#   iam     -> instance profile + OIDC    (Rong)
#   compute -> launch template + ASG      (Rong; runs Hao Ding's scanner image)
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Always pull the latest Amazon Linux 2023 AMI instead of hardcoding an id.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  name = "${var.project}-${var.env}"
}

module "data" {
  source = "./modules/data"

  name        = local.name
  alert_email = var.alert_email
}

module "network" {
  source = "./modules/network"

  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  app_port             = var.app_port
}

module "iam" {
  source = "./modules/iam"

  name                 = local.name
  create_iam           = var.create_iam
  lab_instance_profile = var.lab_instance_profile
  partition            = data.aws_partition.current.partition
  github_repo          = var.github_repo

  reports_bucket_arn = module.data.reports_bucket_arn
  scans_table_arn    = module.data.scans_table_arn
  repos_table_arn    = module.data.repos_table_arn
  vuln_topic_arn     = module.data.vuln_alerts_topic_arn
  failure_topic_arn  = module.data.failure_alerts_topic_arn
}

module "compute" {
  source = "./modules/compute"

  name          = local.name
  env           = var.env
  ami_id        = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type
  asg_desired   = var.asg_desired
  asg_min       = var.asg_min
  asg_max       = var.asg_max
  app_port      = var.app_port
  repo_url      = var.repo_url

  private_subnet_ids   = module.network.private_subnet_ids
  instance_sg_id       = module.network.instance_sg_id
  target_group_arn     = module.network.target_group_arn
  instance_profile_arn = module.iam.instance_profile_arn
}
