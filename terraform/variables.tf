variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used in tags/naming"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Short name used to prefix resource names"
  type        = string
  default     = "cloudproj"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ, used by RDS later)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "AZs to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "my_ip" {
  description = "Your home/current public IP in CIDR form (e.g. 146.75.249.204/32) — the only address allowed to hit the app port directly, until the ALB takes over in Phase 4"
  type        = string
}

variable "app_port" {
  description = "Port the app listens on inside the container"
  type        = number
  default     = 8000
}

variable "instance_type" {
  description = "EC2 instance type — must stay Free Tier eligible"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH fallback. Leave empty to rely on SSM Session Manager only (recommended)."
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Postgres database name"
  type        = string
  default     = "cloudproj"
}

variable "db_username" {
  description = "Postgres master username"
  type        = string
  default     = "appuser"
}

variable "db_instance_class" {
  description = "RDS instance class — must stay Free Tier eligible"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage in GB — Free Tier covers up to 20GB"
  type        = number
  default     = 20
}
