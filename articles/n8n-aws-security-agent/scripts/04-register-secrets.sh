#!/usr/bin/env bash
# Step 04: Register the n8n webhook bearer token and Slack webhook URL into SSM Parameter Store.
# All secret values are read from environment variables that the operator exports in their
# shell session. Nothing is hard-coded.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

: "${N8N_WEBHOOK_BEARER:?N8N_WEBHOOK_BEARER must be exported. Generate one with: openssl rand -hex 32 (then export the value, do not echo it into the repo)}"
: "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL must be exported (https://hooks.slack.com/services/...)}"
: "${KMS_ALIAS:=alias/n8n-secrets}"

echo "[step 04] Register webhook bearer token into SSM SecureString"
aws ssm put-parameter \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --name /n8n/prod/security-agent/webhook-token \
  --value "$N8N_WEBHOOK_BEARER" \
  --type SecureString \
  --key-id "$KMS_ALIAS" \
  --tier Standard \
  --overwrite >/dev/null

echo "[step 04] Register Slack webhook URL into SSM SecureString"
aws ssm put-parameter \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --name /n8n/prod/slack/aws-security-alerts/webhook-url \
  --value "$SLACK_WEBHOOK_URL" \
  --type SecureString \
  --key-id "$KMS_ALIAS" \
  --tier Standard \
  --overwrite >/dev/null

echo "[step 04] done. Stored values are referenced by relay Lambda (SSM_TOKEN_NAME) and by Slack notify HTTP node."
echo "[step 04] Reminder: clear the bearer token from your shell history."
