#!/bin/bash
set -euxo pipefail

# Amazon Linux 2023 bootstrap for a SecureGate scanner node.
# In production the SAST scanner Docker image is pulled here; for the infra
# milestone we run a tiny nginx so the ALB target group reports healthy and
# the load balancer DNS returns a live response.

# Note: skip "dnf update -y" on boot — it can take minutes and push nginx past
# the ALB health-check grace window, causing the ASG to recycle the instance.
dnf install -y nginx

# /health endpoint for the ALB target group health check
echo "ok" > /usr/share/nginx/html/health

cat > /usr/share/nginx/html/index.html <<'HTML'
<!doctype html>
<html>
  <head><title>SecureGate ${service}</title></head>
  <body style="font-family: sans-serif">
    <h1>SecureGate &mdash; ${service} node</h1>
    <p>Provisioned by Terraform. Infrastructure owner: Rong Huang (Group 03).</p>
    <p>Environment: ${env}</p>
  </body>
</html>
HTML

systemctl enable nginx
systemctl start nginx
