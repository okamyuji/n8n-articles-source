#!/usr/bin/env bash
# Sourced by every script in scripts/. Validates required env vars and exposes derived values.
# Do NOT execute directly.

set -euo pipefail

: "${AWS_PROFILE:?AWS_PROFILE must be exported}"
: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION must be exported (e.g. ap-northeast-1)}"

if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
  export AWS_ACCOUNT_ID
fi

ARTICLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ARTICLE_DIR

echo "[common] profile=$AWS_PROFILE region=$AWS_DEFAULT_REGION account=$AWS_ACCOUNT_ID"
