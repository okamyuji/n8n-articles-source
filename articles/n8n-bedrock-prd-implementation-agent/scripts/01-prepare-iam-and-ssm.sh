#!/usr/bin/env bash
# Step 01: Create the IAM role+policy for prd-design-bedrock-implementer Lambda
# and store the GitHub Personal Access Token into SSM SecureString.
#
# Required env vars:
#   GITHUB_TOKEN  GitHub PAT with `repo` and `pull-requests` scopes.
#                 Generate at https://github.com/settings/personal-access-tokens
#                 Pass it via:  export GITHUB_TOKEN=...
#                 The value is sent only to AWS SSM. It is NEVER written to disk by this script.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

: "${GITHUB_TOKEN:?GITHUB_TOKEN must be exported (PAT with repo/pull-requests scopes)}"

IAM_DIR="$ARTICLE_DIR/iam"
ROLE_NAME=prd-design-bedrock-implementer-role
POLICY_NAME=prd-design-bedrock-implementer-policy
PARAM_NAME=/prd-agent/prod/github-token

echo "[step 01] put GitHub token into SSM"
aws ssm put-parameter \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --name "$PARAM_NAME" \
  --value "$GITHUB_TOKEN" \
  --type SecureString \
  --overwrite >/dev/null
echo "[step 01]   ok: $PARAM_NAME"

echo "[step 01] ensure IAM role"
if aws iam get-role --profile "$AWS_PROFILE" --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "[step 01]   role exists: $ROLE_NAME"
else
  aws iam create-role \
    --profile "$AWS_PROFILE" \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://$IAM_DIR/lambda-trust-policy.json" >/dev/null
fi

echo "[step 01] ensure IAM customer-managed policy"
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
RENDERED="$(envsubst '${AWS_ACCOUNT_ID} ${AWS_DEFAULT_REGION}' < "$IAM_DIR/implementer-policy.json")"
if aws iam get-policy --profile "$AWS_PROFILE" --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  printf '%s' "$RENDERED" | aws iam create-policy-version \
    --profile "$AWS_PROFILE" \
    --policy-arn "$POLICY_ARN" \
    --policy-document file:///dev/stdin \
    --set-as-default >/dev/null
  echo "[step 01]   policy updated"
else
  printf '%s' "$RENDERED" | aws iam create-policy \
    --profile "$AWS_PROFILE" \
    --policy-name "$POLICY_NAME" \
    --policy-document file:///dev/stdin >/dev/null
  echo "[step 01]   policy created"
fi
aws iam attach-role-policy \
  --profile "$AWS_PROFILE" \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN" >/dev/null || true

echo "[step 01] done. Role: $ROLE_NAME, Param: $PARAM_NAME"
echo "[step 01] Reminder: clear GITHUB_TOKEN from your shell scrollback when finished."
