#!/bin/bash
# Redirect all output to a log file for post-boot troubleshooting.
exec > >(tee /var/log/sast-bootstrap.log) 2>&1
set -euxo pipefail

# Amazon Linux 2023 bootstrap for a SecureGate ${env} node.
# Pulls a pre-built Docker image from Docker Hub and runs the SAST scanner
# as a container on port ${app_port}. The ALB target group health-checks
# GET /health on this port, which the scanner serves with a 200.

# Install and start Docker — AL2023 uses dnf.
dnf install -y docker
systemctl start docker
systemctl enable docker

# Pull the pre-built SAST scanner image from Docker Hub.
docker pull yinnalucky/securegate-sast:latest

# Run the container — restart always so it survives crashes and reboots.
docker run -d \
  --name sast-scanner \
  --restart always \
  -p ${app_port}:3000 \
  yinnalucky/securegate-sast:latest

# Health check — poll up to 10 times (50s total) before failing the bootstrap.
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf http://localhost:${app_port}/health > /dev/null; then
    echo "Health check passed on attempt $i"
    exit 0
  fi
  echo "Attempt $i: not ready yet, waiting 5s..."
  sleep 5
done

echo "ERROR: scanner did not become healthy after 50s" >&2
exit 1
