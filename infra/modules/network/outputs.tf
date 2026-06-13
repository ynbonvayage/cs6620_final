output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "instance_sg_id" {
  description = "Security group for the scanner instances (ALB-only ingress)"
  value       = aws_security_group.instance.id
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.scanner.arn
}

output "alb_arn" {
  value = aws_lb.app.arn
}
