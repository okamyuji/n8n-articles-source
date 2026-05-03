#!/usr/bin/env bash
# Step 03: Create the dedicated IAM user `n8n-runtime-user` (or extend its inline policy)
# so that n8n can InvokeFunction the prd-design-bedrock-implementer Lambda.
# If you already created this user in article 2, this script only attaches the additional
# policy statement (idempotent put-user-policy with a different name).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

IAM_DIR="$ARTICLE_DIR/iam"
USER_NAME=n8n-runtime-user

if aws iam get-user --profile "$AWS_PROFILE" --user-name "$USER_NAME" >/dev/null 2>&1; then
  echo "[step 03] user exists: $USER_NAME"
else
  aws iam create-user --profile "$AWS_PROFILE" --user-name "$USER_NAME" >/dev/null
fi

envsubst '${AWS_ACCOUNT_ID} ${AWS_DEFAULT_REGION}' < "$IAM_DIR/n8n-runtime-policy.json" \
  | aws iam put-user-policy \
      --profile "$AWS_PROFILE" \
      --user-name "$USER_NAME" \
      --policy-name N8nPrdAgentInvokePolicy \
      --policy-document file:///dev/stdin

echo "[step 03] done. attach access key separately if not yet issued."
