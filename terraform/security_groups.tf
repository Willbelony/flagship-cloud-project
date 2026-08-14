############################################
# Security group — app instance
#
# Inbound: only the app port, only from your IP. No port 22 —
# shell access happens through SSM Session Manager instead, so there's
# no SSH port exposed to the internet at all.
#
# Outbound: all allowed, so the instance can pull Docker images,
# apt/dnf packages, and talk to the SSM service endpoints.
############################################

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow app port from admin IP only; no inbound SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}
