#!/usr/bin/env bash
# Step 03: Wire GuardDuty -> EventBridge -> relay Lambda.
# Re-runnable: put-rule / add-permission / put-targets are all upserts (with caveats).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/guardduty-pattern.json" <<'JSON'
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"]
}
JSON

aws events put-rule \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --name aws-security-guardduty-to-n8n \
  --event-pattern "file://$WORKDIR/guardduty-pattern.json" \
  --state ENABLED >/dev/null

# add-permission fails when the statement-id already exists. Treat as success.
aws lambda add-permission \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --function-name aws-security-relay-to-n8n \
  --statement-id allow-eventbridge \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn "arn:aws:events:${AWS_DEFAULT_REGION}:${AWS_ACCOUNT_ID}:rule/aws-security-guardduty-to-n8n" \
  >/dev/null 2>&1 || echo "[step 03] add-permission already exists (skipping)"

aws events put-targets \
  --profile "$AWS_PROFILE" --region "$AWS_DEFAULT_REGION" \
  --rule aws-security-guardduty-to-n8n \
  --targets "Id=1,Arn=arn:aws:lambda:${AWS_DEFAULT_REGION}:${AWS_ACCOUNT_ID}:function:aws-security-relay-to-n8n" \
  >/dev/null

echo "[step 03] done. EventBridge rule -> aws-security-relay-to-n8n is wired."
