#!/usr/bin/env bash
# Step 99: SUGGESTED cleanup commands. Destructive actions are commented out by default.
# Uncomment lines you really want to execute and run individually.
#
# This script never executes anything destructive on its own.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

cat <<EOF
Suggested teardown commands (review and run individually):

# Disable EventBridge rule first to stop new invocations
# aws events disable-rule --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --name aws-security-guardduty-to-n8n
# aws events remove-targets --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --rule aws-security-guardduty-to-n8n --ids 1
# aws events delete-rule --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --name aws-security-guardduty-to-n8n

# Lambda functions
# aws lambda delete-function --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --function-name aws-security-investigator-readonly
# aws lambda delete-function --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --function-name aws-security-relay-to-n8n
# aws lambda delete-function --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --function-name aws-security-bedrock-summarize

# IAM roles (detach + delete)
# for r in lambda-aws-security-investigator-role lambda-aws-security-relay-role lambda-aws-security-bedrock-role; do
#   aws iam delete-role-policy --profile "\$AWS_PROFILE" --role-name "\$r" --policy-name InvestigatorReadOnly 2>/dev/null || true
#   aws iam delete-role-policy --profile "\$AWS_PROFILE" --role-name "\$r" --policy-name RelayWebhookTokenAccess 2>/dev/null || true
#   aws iam delete-role-policy --profile "\$AWS_PROFILE" --role-name "\$r" --policy-name BedrockInvokeOnly 2>/dev/null || true
#   aws iam detach-role-policy --profile "\$AWS_PROFILE" --role-name "\$r" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
#   aws iam delete-role --profile "\$AWS_PROFILE" --role-name "\$r"
# done

# n8n IAM user
# aws iam delete-user-policy --profile "\$AWS_PROFILE" --user-name n8n-runtime-user --policy-name N8nRuntimePolicy
# aws iam list-access-keys --profile "\$AWS_PROFILE" --user-name n8n-runtime-user --query 'AccessKeyMetadata[].AccessKeyId' --output text \
#   | xargs -n1 -I{} aws iam delete-access-key --profile "\$AWS_PROFILE" --user-name n8n-runtime-user --access-key-id {}
# aws iam delete-user --profile "\$AWS_PROFILE" --user-name n8n-runtime-user

# SSM parameters (Slack URL and webhook token)
# aws ssm delete-parameter --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --name /n8n/prod/security-agent/webhook-token
# aws ssm delete-parameter --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --name /n8n/prod/slack/aws-security-alerts/webhook-url

# GuardDuty detector (BEWARE: also deletes finding history)
# aws guardduty list-detectors --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION"
# aws guardduty delete-detector --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --detector-id <DETECTOR_ID>
EOF
