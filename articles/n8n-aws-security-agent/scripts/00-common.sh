#!/usr/bin/env bash
# Sourced by every script in scripts/. Validates required env vars and exposes derived values.
# Do NOT execute directly.

set -euo pipefail

: "${AWS_PROFILE:?AWS_PROFILE must be exported (e.g. export AWS_PROFILE=n8n-admin)}"
: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION must be exported (e.g. export AWS_DEFAULT_REGION=ap-northeast-1)}"

# AWS_ACCOUNT_ID is auto-resolved if not provided.
if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --profile "$AWS_PROFILE" \
    --query Account --output text)
  export AWS_ACCOUNT_ID
fi

repo_root() {
  # Resolve absolute path of articles/n8n-aws-security-agent/
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

ARTICLE_DIR="$(repo_root)"
export ARTICLE_DIR

echo "[common] AWS_PROFILE=$AWS_PROFILE region=$AWS_DEFAULT_REGION account=$AWS_ACCOUNT_ID"
