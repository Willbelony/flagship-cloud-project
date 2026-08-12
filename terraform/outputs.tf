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
