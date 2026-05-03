#!/usr/bin/env bash
# Step 01: Create the customer-managed KMS key (alias/n8n-secrets) and seed SSM
# Parameter Store with the values that the EC2 instance will load at boot.
#
# Required env vars:
#   N8N_DOMAIN                    fully qualified hostname for n8n (e.g. n8n.example.com)
# Optional env vars:
#   N8N_ENCRYPTION_KEY            32-byte hex; generated locally if unset
#   N8N_DB_PASSWORD               24-byte hex; generated locally if unset
#   USER_MANAGEMENT_DISABLED      true|false (default true)
#   N8N_BLOCK_ENV_ACCESS_IN_NODE  true|false (default false; article 3 needs false)
# All generated secrets are exported into your shell ONLY for the duration of this script
# and never written to disk.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

: "${N8N_DOMAIN:?N8N_DOMAIN must be exported (e.g. n8n.example.com)}"

KEY_ALIAS="alias/n8n-secrets"
SSM_PREFIX="/n8n/prod"

echo "[step 01] ensure KMS key + alias"
if aws kms describe-key --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" --key-id "$KEY_ALIAS" >/dev/null 2>&1; then
  KMS_KEY_ID=$(aws kms describe-key --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" --key-id "$KEY_ALIAS" --query 'KeyMetadata.KeyId' --output text)
  echo "[step 01]   key exists: $KMS_KEY_ID ($KEY_ALIAS)"
else
  KMS_KEY_ID=$(aws kms create-key \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --description "n8n secrets encryption key" \
    --key-usage ENCRYPT_DECRYPT \
    --tags TagKey=Project,TagValue=n8n \
    --query 'KeyMetadata.KeyId' --output text)
  aws kms create-alias \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --alias-name "$KEY_ALIAS" --target-key-id "$KMS_KEY_ID"
  echo "[step 01]   key created: $KMS_KEY_ID"
fi
export KMS_KEY_ID
echo "KMS_KEY_ID=$KMS_KEY_ID  (export this in your shell so step 02 can render the IAM policy)"

# Generate secrets locally if not provided. They never touch disk.
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(openssl rand -hex 32)}"
N8N_DB_PASSWORD="${N8N_DB_PASSWORD:-$(openssl rand -hex 24)}"
USER_MANAGEMENT_DISABLED="${USER_MANAGEMENT_DISABLED:-true}"
N8N_BLOCK_ENV_ACCESS_IN_NODE="${N8N_BLOCK_ENV_ACCESS_IN_NODE:-false}"

put_secure() {
  aws ssm put-parameter \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --name "$1" --value "$2" --type SecureString \
    --key-id "$KEY_ALIAS" --tier Standard --overwrite >/dev/null
  echo "[step 01]   put SecureString: $1"
}
put_string() {
  aws ssm put-parameter \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --name "$1" --value "$2" --type String --overwrite >/dev/null
  echo "[step 01]   put String: $1"
}

put_secure "${SSM_PREFIX}/encryption_key" "$N8N_ENCRYPTION_KEY"
put_secure "${SSM_PREFIX}/db_password"    "$N8N_DB_PASSWORD"
put_string "${SSM_PREFIX}/db_user"        "n8n"
put_string "${SSM_PREFIX}/db_name"        "n8n"
put_string "${SSM_PREFIX}/domain"         "$N8N_DOMAIN"
put_string "${SSM_PREFIX}/user_management_disabled" "$USER_MANAGEMENT_DISABLED"
put_string "${SSM_PREFIX}/n8n_block_env_access_in_node" "$N8N_BLOCK_ENV_ACCESS_IN_NODE"

unset N8N_ENCRYPTION_KEY N8N_DB_PASSWORD
echo "[step 01] done. Reminder: history -c (zsh: history -p) to clear this session's secrets."
