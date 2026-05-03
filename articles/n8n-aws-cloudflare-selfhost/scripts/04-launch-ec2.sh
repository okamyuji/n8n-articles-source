#!/usr/bin/env bash
# Step 04: Launch the t4g.small EC2 instance with the n8n-instance-profile attached and
# ec2/bootstrap.sh as user-data. Outputs INSTANCE_ID for the next step.
#
# Required env vars:
#   SG_ID  printed by step 03 (security group id)
# Optional:
#   KEY_NAME       defaults to n8n-key
#   INSTANCE_TYPE  defaults to t4g.small

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

: "${SG_ID:?SG_ID must be exported (printed by step 03)}"

KEY_NAME="${KEY_NAME:-n8n-key}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t4g.small}"
PROFILE_NAME="n8n-instance-profile"
USER_DATA_FILE="$ARTICLE_DIR/ec2/bootstrap.sh"

# Latest Canonical Ubuntu 24.04 ARM64
AMI_ID=$(aws ec2 describe-images \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --owners 099720109477 \
  --filters \
    "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*" \
    "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text)
echo "[step 04] ami: $AMI_ID"

INSTANCE_ID=$(aws ec2 run-instances \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile "Name=$PROFILE_NAME" \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=2" \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","Encrypted":true}}]' \
  --user-data "file://$USER_DATA_FILE" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=n8n-prod},{Key=Project,Value=n8n}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "[step 04] launched: $INSTANCE_ID"
echo "INSTANCE_ID=$INSTANCE_ID"
echo "[step 04] tail /var/log/cloud-init-output.log via SSH to watch bootstrap progress."
