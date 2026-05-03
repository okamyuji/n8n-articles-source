#!/usr/bin/env bash
# Step 04: Print the manual instructions for injecting PRD_AGENT_FORM_SECRET into the n8n
# container's environment. The form-trigger workflow's "Verify Shared Secret" code node
# reads this value via $env.PRD_AGENT_FORM_SECRET, so it must be present at process start.
#
# We intentionally do NOT push the secret automatically. The operator should:
#   1) generate the secret with `openssl rand -base64 32`
#   2) paste it into the n8n EC2's docker-compose.yml under the n8n service environment
#   3) restart the n8n container
# Doing it by hand keeps the secret out of any local script history.

set -euo pipefail

cat <<'EOF'
[step 04] Manual instructions:

1) On your local machine, generate a strong shared secret and copy it to your clipboard.
   Do NOT echo it to a file you commit:
   $ openssl rand -base64 32 | pbcopy

2) SSH into the n8n EC2 host:
   $ ssh -i ~/.ssh/n8n-key.pem ubuntu@<your-ec2-ip>

3) Edit ~/n8n/docker-compose.yml (or wherever your compose file lives) and add under the
   n8n service's environment block:
     environment:
       - PRD_AGENT_FORM_SECRET=<paste here>

4) Restart the n8n container:
   $ sudo docker compose -f ~/n8n/docker-compose.yml up -d n8n

5) Distribute the same secret out-of-band to the people allowed to use the form (1Password,
   Slack DM, etc.). They paste it into the form's "Shared Secret" field on each submission.

6) Rotate the secret periodically by repeating steps 1-5 with a freshly generated value.
EOF
