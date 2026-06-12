output "instance_profile_arn" {
  description = "Instance profile attached to the scanner fleet"
  value       = local.instance_profile_arn
}

output "github_ci_role_arn" {
  description = "Keyless CI role assumed by GitHub Actions (only when create_iam = true)"
  value       = var.create_iam ? aws_iam_role.github_ci[0].arn : "not created — Learner Lab blocks iam:CreateRole"
}
