#!/usr/bin/env bash
# Step 99: SUGGESTED cleanup commands. Destructive actions are commented out by default.
# Uncomment lines you really want to execute and run individually.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

cat <<EOF
Suggested teardown for article 3 (review and run individually):

# Lambda
# aws lambda delete-function --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" \\
#   --function-name prd-design-bedrock-implementer

# IAM customer-managed policy + role
# POLICY_ARN="arn:aws:iam::\${AWS_ACCOUNT_ID}:policy/prd-design-bedrock-implementer-policy"
# aws iam detach-role-policy --profile "\$AWS_PROFILE" \\
#   --role-name prd-design-bedrock-implementer-role --policy-arn "\$POLICY_ARN" 2>/dev/null || true
# aws iam list-policy-versions --profile "\$AWS_PROFILE" --policy-arn "\$POLICY_ARN" \\
#   --query 'Versions[?!IsDefaultVersion].VersionId' --output text \\
#   | xargs -n1 -I{} aws iam delete-policy-version --profile "\$AWS_PROFILE" --policy-arn "\$POLICY_ARN" --version-id {} 2>/dev/null || true
# aws iam delete-policy --profile "\$AWS_PROFILE" --policy-arn "\$POLICY_ARN"
# aws iam delete-role --profile "\$AWS_PROFILE" --role-name prd-design-bedrock-implementer-role

# n8n IAM user inline policy added by step 03
# aws iam delete-user-policy --profile "\$AWS_PROFILE" \\
#   --user-name n8n-runtime-user --policy-name N8nPrdAgentInvokePolicy

# SSM
# aws ssm delete-parameter --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" \\
#   --name /prd-agent/prod/github-token

# Form secret on n8n container: rotate or remove the env var manually on the EC2 host
EOF
