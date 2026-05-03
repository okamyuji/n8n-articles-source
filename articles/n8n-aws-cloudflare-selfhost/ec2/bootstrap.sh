#!/usr/bin/env bash
# EC2 user-data. Installs Docker / AWS CLI v2, drops the n8n compose stack into /opt/n8n,
# and wires the systemd units so secrets are reloaded from SSM into tmpfs at every boot.
#
# Sibling files in this directory (load-secrets.sh, docker-compose.yml.template,
# Caddyfile.template, n8n-secrets.service, docker-n8n.service) are inlined here as
# heredocs so the EC2 instance can boot without any further file fetch.

set -euxo pipefail

REGION="ap-northeast-1"

# 1. Base packages + AWS CLI v2 (architecture-aware download)
apt-get update
apt-get install -y ca-certificates curl gnupg unzip jq
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  AWS_ZIP="awscli-exe-linux-aarch64.zip"
else
  AWS_ZIP="awscli-exe-linux-x86_64.zip"
fi
curl -sSL "https://awscli.amazonaws.com/${AWS_ZIP}" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# 2. Docker engine + compose plugin (official repo)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
DEB_ARCH=$(dpkg --print-architecture)
echo "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Cap container log size so a runaway workflow does not fill the disk.
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
systemctl restart docker

# 3. Application directory
mkdir -p /opt/n8n /opt/n8n/cron

# 4. load-secrets.sh — pulls every /n8n/prod/* SSM parameter into tmpfs as KEY=VALUE.
cat > /opt/n8n/load-secrets.sh <<'INNER'
#!/bin/bash
set -euo pipefail
REGION="ap-northeast-1"
SSM_PREFIX="/n8n/prod"
ENV_FILE="/run/n8n-secrets/.env"
if ! mountpoint -q /run/n8n-secrets; then
  mkdir -p /run/n8n-secrets
  mount -t tmpfs -o size=1M,mode=0700 tmpfs /run/n8n-secrets
fi
PARAMS=$(aws ssm get-parameters-by-path \
  --region "$REGION" --path "$SSM_PREFIX" --recursive --with-decryption \
  --query 'Parameters[].[Name,Value]' --output text)
{
  echo "# Auto-generated. Lives only in tmpfs. Do not edit."
  while IFS=$'\t' read -r name value; do
    var_name=$(echo "$name" | sed "s|^${SSM_PREFIX}/||" | tr '[:lower:]' '[:upper:]')
    echo "${var_name}=${value}"
  done <<< "$PARAMS"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"
echo "Loaded $(($(wc -l < "$ENV_FILE") - 1)) secrets to $ENV_FILE"
INNER
chmod +x /opt/n8n/load-secrets.sh

# 5. systemd unit: secrets loader (runs before docker compose)
cat > /etc/systemd/system/n8n-secrets.service <<'EOF'
[Unit]
Description=Load n8n secrets from SSM into tmpfs
After=network-online.target
Wants=network-online.target
Before=docker-n8n.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/mkdir -p /run/n8n-secrets
ExecStartPre=/bin/mount -t tmpfs -o size=1M,mode=0700 tmpfs /run/n8n-secrets
ExecStart=/opt/n8n/load-secrets.sh
ExecStop=/bin/umount /run/n8n-secrets

[Install]
WantedBy=multi-user.target
EOF

# 6. docker-compose.yml (env_file is the tmpfs file from step 5)
cat > /opt/n8n/docker-compose.yml <<'YAML'
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 10

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${DB_NAME}
      DB_POSTGRESDB_USER: ${DB_USER}
      DB_POSTGRESDB_PASSWORD: ${DB_PASSWORD}
      N8N_ENCRYPTION_KEY: ${ENCRYPTION_KEY}
      N8N_HOST: ${DOMAIN}
      N8N_PROTOCOL: https
      N8N_PORT: 5678
      WEBHOOK_URL: https://${DOMAIN}/
      GENERIC_TIMEZONE: Asia/Tokyo
      TZ: Asia/Tokyo
      EXECUTIONS_DATA_PRUNE: "true"
      EXECUTIONS_DATA_MAX_AGE: "168"
      N8N_USER_MANAGEMENT_DISABLED: ${USER_MANAGEMENT_DISABLED:-false}
      N8N_BLOCK_ENV_ACCESS_IN_NODE: ${N8N_BLOCK_ENV_ACCESS_IN_NODE:-false}
      PRD_AGENT_FORM_SECRET: ${PRD_AGENT_FORM_SECRET:-}
    volumes:
      - n8n_data:/home/node/.n8n

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      DOMAIN: ${DOMAIN}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n

volumes:
  postgres_data:
  n8n_data:
  caddy_data:
  caddy_config:
YAML

# 7. Caddyfile (auto TLS via Let's Encrypt + WebSocket support)
cat > /opt/n8n/Caddyfile <<'EOF'
{$DOMAIN} {
    reverse_proxy n8n:5678
    encode gzip

    @websocket {
        header Connection *Upgrade*
        header Upgrade websocket
    }
    reverse_proxy @websocket n8n:5678
}
EOF

# 8. systemd unit: docker compose (depends on n8n-secrets.service)
cat > /etc/systemd/system/docker-n8n.service <<'EOF'
[Unit]
Description=n8n via Docker Compose
Requires=docker.service n8n-secrets.service
After=docker.service n8n-secrets.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/n8n
EnvironmentFile=/run/n8n-secrets/.env
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable n8n-secrets.service
systemctl enable docker-n8n.service
systemctl start n8n-secrets.service
systemctl start docker-n8n.service

echo "Bootstrap complete. n8n should be reachable once Caddy obtains its TLS cert."
