#!/usr/bin/env bash
# Step 03: Create the security group (SSH from your IP, HTTP/443 from anywhere) and
# the SSH key pair. Auto-detects your current public IP if MY_IP is not exported.
#
# Outputs the SG_ID variable line so you can `eval $(...)` if you want.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

KEY_NAME="${KEY_NAME:-n8n-key}"
KEY_PATH="${KEY_PATH:-$HOME/.ssh/n8n-key.pem}"
SG_NAME="${SG_NAME:-n8n-sg}"

if [[ -z "${MY_IP:-}" ]]; then
  MY_IP=$(curl -s https://checkip.amazonaws.com)
fi
echo "[step 03] using MY_IP=$MY_IP for SSH ingress"

VPC_ID=$(aws ec2 describe-vpcs \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --filters "Name=is-default,Values=true" \
  --query 'Vpcs[0].VpcId' --output text)

if SG_ID=$(aws ec2 describe-security-groups \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null) && [[ "$SG_ID" != "None" ]]; then
  echo "[step 03] security group exists: $SG_ID ($SG_NAME)"
else
  SG_ID=$(aws ec2 create-security-group \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --group-name "$SG_NAME" \
    --description "n8n web access" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text)
  echo "[step 03] security group created: $SG_ID"
fi
export SG_ID
echo "SG_ID=$SG_ID"

authorize_if_missing() {
  local proto="$1" port="$2" cidr="$3"
  aws ec2 authorize-security-group-ingress \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --group-id "$SG_ID" --protocol "$proto" --port "$port" --cidr "$cidr" \
    >/dev/null 2>&1 \
    && echo "[step 03]   added rule: $proto/$port from $cidr" \
    || echo "[step 03]   rule already present: $proto/$port from $cidr"
}

authorize_if_missing tcp 22 "${MY_IP}/32"
authorize_if_missing tcp 80 "0.0.0.0/0"
authorize_if_missing tcp 443 "0.0.0.0/0"

if [[ -f "$KEY_PATH" ]]; then
  echo "[step 03] key file exists: $KEY_PATH (skipping create-key-pair)"
else
  aws ec2 create-key-pair \
    --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
    --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "$KEY_PATH"
  chmod 600 "$KEY_PATH"
  echo "[step 03] key pair created: $KEY_NAME -> $KEY_PATH"
fi
