#!/usr/bin/env bash
# Step 02: Create the EC2 instance role n8n-instance-role with the minimum policy
# (read /n8n/prod/* SSM params, decrypt with the customer-managed KMS key) and the
# matching instance profile.
#
# Required env vars:
#   KMS_KEY_ID  uuid printed by step 01

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

: "${KMS_KEY_ID:?KMS_KEY_ID must be exported (printed by step 01)}"

IAM_DIR="$ARTICLE_DIR/iam"
ROLE_NAME=n8n-instance-role
PROFILE_NAME=n8n-instance-profile

if aws iam get-role --profile "$AWS_PROFILE" --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "[step 02] role exists: $ROLE_NAME"
else
  aws iam create-role \
    --profile "$AWS_PROFILE" \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://$IAM_DIR/n8n-ec2-trust-policy.json" \
    --description "Allows n8n EC2 instance to read SSM parameters" >/dev/null
fi

envsubst '${AWS_ACCOUNT_ID} ${AWS_DEFAULT_REGION} ${KMS_KEY_ID}' < "$IAM_DIR/n8n-ec2-permission-policy.json" \
  | aws iam put-role-policy \
      --profile "$AWS_PROFILE" \
      --role-name "$ROLE_NAME" \
      --policy-name n8n-ssm-read \
      --policy-document file:///dev/stdin

if aws iam get-instance-profile --profile "$AWS_PROFILE" --instance-profile-name "$PROFILE_NAME" >/dev/null 2>&1; then
  echo "[step 02] instance-profile exists: $PROFILE_NAME"
else
  aws iam create-instance-profile --profile "$AWS_PROFILE" --instance-profile-name "$PROFILE_NAME" >/dev/null
  aws iam add-role-to-instance-profile \
    --profile "$AWS_PROFILE" \
    --instance-profile-name "$PROFILE_NAME" \
    --role-name "$ROLE_NAME"
  echo "[step 02] waiting 15s for IAM propagation..."
  sleep 15
fi

aws iam get-instance-profile --profile "$AWS_PROFILE" --instance-profile-name "$PROFILE_NAME" \
  --query 'InstanceProfile.[InstanceProfileName,Roles[0].RoleName]' --output table
