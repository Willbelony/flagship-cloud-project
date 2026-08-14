output "vpc_id" {
  description = "ID of the VPC — referenced by EC2/RDS/ALB in later phases"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (app + load balancer)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (database)"
  value       = aws_subnet.private[*].id
}

output "app_instance_id" {
  description = "EC2 instance ID — use with 'aws ssm start-session --target <id>'"
  value       = aws_instance.app.id
}

output "app_public_ip" {
  description = "Public IP of the app instance"
  value       = aws_instance.app.public_ip
}

output "db_endpoint" {
  description = "RDS Postgres endpoint (host:port) — the password itself is never output; it's in SSM Parameter Store"
  value       = aws_db_instance.main.endpoint
}

output "db_param_name" {
  description = "SSM Parameter Store key holding the full DATABASE_URL"
  value       = aws_ssm_parameter.database_url.name
}

output "alb_dns_name" {
  description = "ALB's public DNS name — usable immediately, before the domain is wired up"
  value       = aws_lb.main.dns_name
}

output "ecr_repository_url" {
  description = "ECR repo URL — used by the GitHub Actions workflow to push images"
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "IAM role ARN GitHub Actions assumes via OIDC — put this in the workflow file"
  value       = aws_iam_role.github_actions_deploy.arn
}

output "cloudwatch_dashboard_url" {
  description = "Direct link to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
