#!/usr/bin/env bash
# Step 02: Build and deploy the 3 Lambda functions.
# Re-runnable: existing functions are updated via update-function-code.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

LAMBDA_DIR="$ARTICLE_DIR/lambda"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

: "${N8N_WEBHOOK_URL:?N8N_WEBHOOK_URL must be exported (https://your-n8n-domain/webhook/aws-security-finding). Until n8n is set up, you may pass a placeholder and re-run after step 04.}"

build_zip() {
  # build_zip <function_dir>
  local fdir="$1"
  local name; name="$(basename "$fdir")"
  local out="$WORKDIR/${name}.zip"
  echo "[step 02] build $name"
  ( cd "$fdir" && npm install --omit=dev --silent )
  ( cd "$fdir" && zip -qr "$out" index.mjs node_modules package.json )
  echo "$out"
}

deploy_function() {
  # deploy_function <function-name> <role-arn> <handler> <env-block> <zip-path> <timeout> <mem>
  local fn="$1" role_arn="$2" handler="$3" env_block="$4" zip="$5" timeout="$6" mem="$7"
  if aws lambda get-function \
       --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
       --function-name "$fn" >/dev/null 2>&1; then
    echo "[step 02]   update-function-code: $fn"
    aws lambda update-function-code \
      --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
      --function-name "$fn" \
      --zip-file "fileb://$zip" >/dev/null
    aws lambda update-function-configuration \
      --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
      --function-name "$fn" \
      --timeout "$timeout" --memory-size "$mem" \
      --environment "Variables={$env_block}" >/dev/null
  else
    echo "[step 02]   create-function: $fn"
    aws lambda create-function \
      --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
      --function-name "$fn" \
      --runtime nodejs24.x \
      --handler "$handler" \
      --role "$role_arn" \
      --timeout "$timeout" --memory-size "$mem" \
      --environment "Variables={$env_block}" \
      --zip-file "fileb://$zip" >/dev/null
  fi
}

investigator_zip=$(build_zip "$LAMBDA_DIR/investigator")
deploy_function aws-security-investigator-readonly \
  "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-aws-security-investigator-role" \
  index.handler \
  "LOOKBACK_HOURS=24,MAX_EVENTS=50" \
  "$investigator_zip" 30 256

relay_zip=$(build_zip "$LAMBDA_DIR/relay")
deploy_function aws-security-relay-to-n8n \
  "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-aws-security-relay-role" \
  index.handler \
  "N8N_WEBHOOK_URL=${N8N_WEBHOOK_URL},SSM_TOKEN_NAME=/n8n/prod/security-agent/webhook-token" \
  "$relay_zip" 90 128

bedrock_zip=$(build_zip "$LAMBDA_DIR/bedrock")
deploy_function aws-security-bedrock-summarize \
  "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-aws-security-bedrock-role" \
  index.handler \
  "MODEL_ID=${BEDROCK_HAIKU_MODEL_ID:-jp.anthropic.claude-haiku-4-5-20251001-v1:0},MAX_TOKENS=2048" \
  "$bedrock_zip" 60 512

echo "[step 02] done"
