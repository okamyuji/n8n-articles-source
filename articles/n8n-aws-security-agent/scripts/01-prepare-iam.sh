#!/usr/bin/env bash
# Step 01: Enable GuardDuty (idempotent) and create the 3 Lambda execution roles
# (investigator / relay / bedrock) with their inline policies.
#
# Re-runnable: existing roles trigger a non-zero exit on create-role; rerun individual
# put-role-policy/attach-role-policy as needed.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

IAM_DIR="$ARTICLE_DIR/iam"

render_policy() {
  # Replace ${AWS_ACCOUNT_ID}, ${AWS_DEFAULT_REGION}, ${KMS_KEY_ID} in the JSON file.
  local in="$1"
  envsubst '${AWS_ACCOUNT_ID} ${AWS_DEFAULT_REGION} ${KMS_KEY_ID}' < "$in"
}

echo "[step 01] Ensure GuardDuty detector exists"
existing=$(aws guardduty list-detectors \
  --profile "$AWS_PROFILE" \
  --region "$AWS_DEFAULT_REGION" \
  --query 'DetectorIds[0]' --output text)
if [[ "$existing" == "None" || -z "$existing" ]]; then
  aws guardduty create-detector \
    --profile "$AWS_PROFILE" \
    --region "$AWS_DEFAULT_REGION" \
    --enable \
    --finding-publishing-frequency FIFTEEN_MINUTES
else
  echo "[step 01] GuardDuty detector already exists: $existing"
fi

echo "[step 01] Create Lambda execution roles"

create_role_idempotent() {
  local role="$1"
  if aws iam get-role --profile "$AWS_PROFILE" --role-name "$role" >/dev/null 2>&1; then
    echo "[step 01]   role exists: $role"
  else
    aws iam create-role \
      --profile "$AWS_PROFILE" \
      --role-name "$role" \
      --assume-role-policy-document "file://$IAM_DIR/lambda-trust-policy.json"
  fi
  aws iam attach-role-policy \
    --profile "$AWS_PROFILE" \
    --role-name "$role" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
}

create_role_idempotent lambda-aws-security-investigator-role
render_policy "$IAM_DIR/investigator-policy.json" \
  | aws iam put-role-policy \
      --profile "$AWS_PROFILE" \
      --role-name lambda-aws-security-investigator-role \
      --policy-name InvestigatorReadOnly \
      --policy-document file:///dev/stdin

create_role_idempotent lambda-aws-security-relay-role
: "${KMS_KEY_ID:?KMS_KEY_ID must be exported (the n8n-secrets KMS key id from article 1)}"
render_policy "$IAM_DIR/relay-policy.json" \
  | aws iam put-role-policy \
      --profile "$AWS_PROFILE" \
      --role-name lambda-aws-security-relay-role \
      --policy-name RelayWebhookTokenAccess \
      --policy-document file:///dev/stdin

create_role_idempotent lambda-aws-security-bedrock-role
render_policy "$IAM_DIR/bedrock-policy.json" \
  | aws iam put-role-policy \
      --profile "$AWS_PROFILE" \
      --role-name lambda-aws-security-bedrock-role \
      --policy-name BedrockInvokeOnly \
      --policy-document file:///dev/stdin

echo "[step 01] done. roles: lambda-aws-security-{investigator,relay,bedrock}-role"
