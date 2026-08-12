#!/bin/bash
set -euo pipefail

# Amazon Linux 2023 ships the SSM agent pre-installed and running,
# so no setup needed for Session Manager access.

dnf update -y
dnf install -y docker

systemctl enable docker
systemctl start docker

# Let the default ec2-user run docker without sudo
usermod -aG docker ec2-user

# Docker Compose v2 plugin
mkdir -p /usr/libexec/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/libexec/docker/cli-plugins/docker-compose
chmod +x /usr/libexec/docker/cli-plugins/docker-compose

echo "Bootstrap complete" > /var/log/user-data-complete.log
