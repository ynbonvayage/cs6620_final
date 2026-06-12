output "asg_name" {
  value = aws_autoscaling_group.scanner.name
}

output "launch_template_id" {
  value = aws_launch_template.scanner.id
}
