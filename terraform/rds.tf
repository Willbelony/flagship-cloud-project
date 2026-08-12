############################################
# Auto-generated DB password — never typed, never committed,
# never visible in the Terraform diff output (sensitive = true)
############################################

resource "random_password" "db" {
  length  = 24
  special = false # avoids characters that need URL-encoding in a connection string
}

############################################
# DB subnet group — spans both private subnets, as RDS requires
# at least 2 AZs for the subnet group even in single-AZ deployment mode
############################################

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

############################################
# DB security group — only the app instance's security group can
# reach port 5432. Not open to your IP, not open to the internet,
# not even open to the rest of the VPC.
############################################

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Allow Postgres only from the app security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from app instance only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

############################################
# RDS Postgres instance
############################################

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "16"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  multi_az = false # single-AZ — Multi-AZ isn't Free Tier eligible and doubles cost

  backup_retention_period = 1 # minimum viable backups without added cost
  skip_final_snapshot     = true # fine for a portfolio project; a real prod DB would keep a final snapshot
  deletion_protection     = false # so `terraform destroy` can actually tear it down for cost control

  tags = {
    Name = "${var.project_name}-db"
  }
}

############################################
# Store the connection string in SSM Parameter Store as a SecureString.
# The app instance's IAM role gets read-only access to this one parameter —
# nothing else in Parameter Store, and no plaintext password in code, env
# files, or Terraform state diffs shown on screen.
############################################

resource "aws_ssm_parameter" "database_url" {
  name  = "/${var.project_name}/database_url"
  type  = "SecureString"
  value = "postgresql+psycopg2://${var.db_username}:${random_password.db.result}@${aws_db_instance.main.address}:5432/${var.db_name}"

  tags = {
    Name = "${var.project_name}-database-url"
  }
}

data "aws_iam_policy_document" "read_db_param" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.database_url.arn]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"] # SSM SecureString uses the account's default aws/ssm KMS key
  }
}

resource "aws_iam_role_policy" "read_db_param" {
  name   = "${var.project_name}-read-db-param"
  role   = aws_iam_role.app_instance.id
  policy = data.aws_iam_policy_document.read_db_param.json
}
