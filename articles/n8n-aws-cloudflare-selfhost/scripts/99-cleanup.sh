#!/usr/bin/env bash
# Step 99: SUGGESTED cleanup commands. Destructive actions are commented out by default.
# Uncomment lines you really want to execute and run individually.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
. "$SCRIPT_DIR/00-common.sh"

cat <<EOF
Suggested teardown for article 1 (review and run individually):

# 1. Disassociate + release Elastic IP (no charge once detached if released)
# aws ec2 describe-addresses --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION"
# aws ec2 disassociate-address --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --association-id <ASSOC>
# aws ec2 release-address      --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --allocation-id <EIP_ALLOC>

# 2. Terminate EC2 instance
# aws ec2 terminate-instances --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --instance-ids <INSTANCE_ID>
# aws ec2 wait instance-terminated --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --instance-ids <INSTANCE_ID>

# 3. Security group + key pair
# aws ec2 delete-security-group --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --group-name n8n-sg
# aws ec2 delete-key-pair       --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --key-name n8n-key

# 4. Instance profile + role
# aws iam remove-role-from-instance-profile --profile "\$AWS_PROFILE" --instance-profile-name n8n-instance-profile --role-name n8n-instance-role
# aws iam delete-instance-profile --profile "\$AWS_PROFILE" --instance-profile-name n8n-instance-profile
# aws iam delete-role-policy --profile "\$AWS_PROFILE" --role-name n8n-instance-role --policy-name n8n-ssm-read
# aws iam delete-role --profile "\$AWS_PROFILE" --role-name n8n-instance-role

# 5. SSM parameters (BEWARE: losing /n8n/prod/encryption_key bricks all stored credentials)
# aws ssm get-parameters-by-path --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --path /n8n/prod --recursive --query 'Parameters[].Name' --output text \\
#   | xargs -n1 aws ssm delete-parameter --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --name

# 6. KMS key (schedule deletion 7-30 days; cannot be undone after the waiting period)
# aws kms delete-alias --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --alias-name alias/n8n-secrets
# aws kms schedule-key-deletion --profile "\$AWS_PROFILE" --region "\$AWS_DEFAULT_REGION" --key-id <KMS_KEY_ID> --pending-window-in-days 30

# 7. Cloudflare A record: remove via the dashboard.
EOF
