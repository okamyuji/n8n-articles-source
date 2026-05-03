#!/usr/bin/env bash
# Step 05: Create the dedicated IAM user `n8n-runtime-user` and attach the inline policy
# that allows InvokeFunction on the two agent Lambdas. Then issue an access key and print
# it ONCE so the operator can paste it into the n8n AWS credential UI.
#
# CAUTION: AccessKeyId and SecretAccessKey are returned only at creation time. Paste them
# directly into n8n and clear from your shell scrollback. They are not echoed back here.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

IAM_DIR="$ARTICLE_DIR/iam"

if aws iam get-user --profile "$AWS_PROFILE" --user-name n8n-runtime-user >/dev/null 2>&1; then
  echo "[step 05] user already exists: n8n-runtime-user"
else
  aws iam create-user --profile "$AWS_PROFILE" --user-name n8n-runtime-user >/dev/null
fi

envsubst '${AWS_ACCOUNT_ID} ${AWS_DEFAULT_REGION}' < "$IAM_DIR/n8n-runtime-policy.json" \
  | aws iam put-user-policy \
      --profile "$AWS_PROFILE" \
      --user-name n8n-runtime-user \
      --policy-name N8nRuntimePolicy \
      --policy-document file:///dev/stdin

echo "[step 05] Issuing a new access key. Capture both values immediately."
aws iam create-access-key \
  --profile "$AWS_PROFILE" \
  --user-name n8n-runtime-user \
  --output json
echo "[step 05] Reminder: paste into n8n AWS credential and clear shell history."
