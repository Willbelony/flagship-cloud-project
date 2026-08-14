############################################
# ALB security group — the ONLY thing allowed to reach the app port
# on the EC2 instance now. Open to the internet on 80/443 (that's the
# point of a load balancer — it's meant to be public), but the app
# instance itself no longer trusts any IP directly, only this SG.
############################################

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Public HTTP/HTTPS entry point"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}
