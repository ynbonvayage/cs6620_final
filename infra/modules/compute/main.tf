###############################################################################
# Launch template for the scanner fleet
###############################################################################

resource "aws_launch_template" "scanner" {
  name_prefix   = "${var.name}-scanner-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = var.instance_profile_arn
  }

  vpc_security_group_ids = [var.instance_sg_id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    service = "SAST scanner"
    env     = var.env
  }))

  metadata_options {
    http_tokens   = "required" # enforce IMDSv2
    http_endpoint = "enabled"
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name}-scanner"
      Role = "sast-scanner"
    }
  }
}

###############################################################################
# Auto Scaling Group across the private subnets, registered to the ALB TG
###############################################################################

resource "aws_autoscaling_group" "scanner" {
  name                      = "${var.name}-scanner-asg"
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  desired_capacity = var.asg_desired
  min_size         = var.asg_min
  max_size         = var.asg_max

  launch_template {
    id      = aws_launch_template.scanner.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-scanner"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}

# Target-tracking scaling policy on average CPU
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.name}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.scanner.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}
