#!/bin/bash
# Read by /etc/systemd/system/n8n-secrets.service at boot. Pulls every parameter under
# /n8n/prod into a tmpfs-backed env file that docker compose loads via EnvironmentFile.
# Nothing here is written to the EC2 disk persistently.

set -euo pipefail

REGION="ap-northeast-1"
SSM_PREFIX="/n8n/prod"
ENV_FILE="/run/n8n-secrets/.env"

# Make sure tmpfs is mounted (the systemd unit normally does this first).
if ! mountpoint -q /run/n8n-secrets; then
  mkdir -p /run/n8n-secrets
  mount -t tmpfs -o size=1M,mode=0700 tmpfs /run/n8n-secrets
fi

# AWS CLI v2 picks up the EC2 instance role via IMDSv2 automatically.
PARAMS=$(aws ssm get-parameters-by-path \
  --region "$REGION" \
  --path "$SSM_PREFIX" \
  --recursive \
  --with-decryption \
  --query 'Parameters[].[Name,Value]' \
  --output text)

# Convert each /n8n/prod/<key> into <UPPERCASE_KEY>=<value>.
{
  echo "# Auto-generated. Lives only in tmpfs. Do not edit."
  while IFS=$'\t' read -r name value; do
    var_name=$(echo "$name" | sed "s|^${SSM_PREFIX}/||" | tr '[:lower:]' '[:upper:]')
    echo "${var_name}=${value}"
  done <<< "$PARAMS"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Loaded $(($(wc -l < "$ENV_FILE") - 1)) secrets to $ENV_FILE"
