#!/usr/bin/env bash
# Step 05: Allocate an Elastic IP, associate it with the EC2 instance, and print the
# public IP that you should set as your Cloudflare A record (grey cloud / DNS only).
#
# Required env vars:
#   INSTANCE_ID  printed by step 04

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

: "${INSTANCE_ID:?INSTANCE_ID must be exported (printed by step 04)}"

EIP_ALLOC=$(aws ec2 allocate-address \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --domain vpc \
  --query 'AllocationId' --output text)
echo "[step 05] eip allocation: $EIP_ALLOC"

aws ec2 associate-address \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --instance-id "$INSTANCE_ID" \
  --allocation-id "$EIP_ALLOC" >/dev/null

PUBLIC_IP=$(aws ec2 describe-addresses \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --allocation-ids "$EIP_ALLOC" \
  --query 'Addresses[0].PublicIp' --output text)

echo "[step 05] PUBLIC_IP=$PUBLIC_IP"
echo "[step 05] EIP_ALLOC_ID=$EIP_ALLOC"
echo "[step 05] Now create a Cloudflare A record: ${N8N_DOMAIN:-<your-domain>} -> $PUBLIC_IP (DNS only / grey cloud)"
