#!/usr/bin/env bash
# Step 02: Build and deploy the prd-design-bedrock-implementer Lambda function.
# Re-runnable. Uses npm install --omit=dev to keep node_modules out of the zip in dev form.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

LAMBDA_DIR="$ARTICLE_DIR/lambda/prd-design-bedrock-implementer"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

FUNCTION_NAME=prd-design-bedrock-implementer
ROLE_NAME=prd-design-bedrock-implementer-role
PARAM_NAME=/prd-agent/prod/github-token
RUNTIME=nodejs24.x
MODEL_ID="${BEDROCK_SONNET_MODEL_ID:-jp.anthropic.claude-sonnet-4-6}"

echo "[step 02] npm install + zip"
( cd "$LAMBDA_DIR" && npm install --omit=dev --no-package-lock --silent )
( cd "$LAMBDA_DIR" && zip -qr "$WORKDIR/implementer.zip" index.mjs package.json node_modules )
ls -lh "$WORKDIR/implementer.zip"

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

if aws lambda get-function \
     --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
     --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  echo "[step 02] update-function-code"
  aws lambda update-function-code \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$WORKDIR/implementer.zip" >/dev/null
  aws lambda wait function-updated \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --function-name "$FUNCTION_NAME"
  aws lambda update-function-configuration \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --handler index.handler \
    --memory-size 1024 --timeout 300 \
    --role "$ROLE_ARN" \
    --environment "Variables={MODEL_ID=$MODEL_ID,GITHUB_TOKEN_PARAM=$PARAM_NAME}" >/dev/null
else
  echo "[step 02] create-function (waiting for IAM role to propagate)"
  sleep 12
  aws lambda create-function \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --handler index.handler \
    --memory-size 1024 --timeout 300 \
    --role "$ROLE_ARN" \
    --environment "Variables={MODEL_ID=$MODEL_ID,GITHUB_TOKEN_PARAM=$PARAM_NAME}" \
    --zip-file "fileb://$WORKDIR/implementer.zip" >/dev/null
fi

echo "[step 02] done. function=$FUNCTION_NAME model=$MODEL_ID"
