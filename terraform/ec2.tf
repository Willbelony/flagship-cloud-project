############################################
# Latest Amazon Linux 2023 AMI (x86_64)
############################################

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

############################################
# App EC2 instance
#
# Lives in a public subnet with a public IP (simplest for a portfolio
# project reachable directly during Phases 2-3). Once the ALB goes in
# during Phase 4, the security group gets tightened to ALB-only and
# this becomes a private-subnet instance behind it.
############################################

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app_instance.name
  key_name               = var.key_name != "" ? var.key_name : null

  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-app"
  }
}
