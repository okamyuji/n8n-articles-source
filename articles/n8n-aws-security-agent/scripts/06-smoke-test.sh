#!/usr/bin/env bash
# Step 06: Trigger 2 GuardDuty sample findings and watch them flow to Slack via the n8n workflow.
# Always specify --finding-types explicitly. Omitting causes ~130 sample findings at once.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

DETECTOR_ID=$(aws guardduty list-detectors \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --query 'DetectorIds[0]' --output text)

if [[ "$DETECTOR_ID" == "None" || -z "$DETECTOR_ID" ]]; then
  echo "ERROR: no GuardDuty detector found. Run scripts/01-prepare-iam.sh first."
  exit 1
fi

aws guardduty create-sample-findings \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --detector-id "$DETECTOR_ID" \
  --finding-types \
    "Recon:IAMUser/MaliciousIPCaller.Custom" \
    "Trojan:EC2/DropPoint!DNS"

echo "[step 06] sample findings dispatched. Check:"
echo "  - EventBridge metrics (MatchedEvents / Invocations)"
echo "  - relay Lambda CloudWatch Logs (200 response)"
echo "  - n8n Executions UI (success)"
echo "  - your private Slack channel for the summary message"
