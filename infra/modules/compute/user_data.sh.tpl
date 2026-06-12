#!/bin/bash
set -euxo pipefail

# Amazon Linux 2023 bootstrap for a SecureGate ${service} node.
# Clones the repo over NAT egress and runs the Node.js SAST backend as a
# systemd service on port ${app_port}. The ALB target group health-checks
# GET /health on this port, which the scanner serves with a 200.

# Note: skip "dnf update -y" on boot — it can take minutes and push the app
# past the ALB health-check grace window, causing the ASG to recycle the node.
dnf install -y git nodejs npm

# Pull the application source.
git clone ${repo_url} /opt/securegate
cd /opt/securegate/sast/backend
npm install --production

# Run the scanner as a managed service so it restarts on crash/reboot.
cat > /etc/systemd/system/securegate-scanner.service <<UNIT
[Unit]
Description=SecureGate SAST scanner (${env})
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/securegate/sast/backend
Environment=PORT=${app_port}
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable securegate-scanner
systemctl start securegate-scanner
