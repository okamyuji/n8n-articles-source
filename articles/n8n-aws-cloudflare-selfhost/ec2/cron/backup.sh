#!/bin/bash
# Daily Postgres dump uploader. Install via cron entry such as:
#   0 3 * * * /opt/n8n/cron/backup.sh >> /var/log/n8n-backup.log 2>&1

set -euo pipefail
cd /opt/n8n

# Set BACKUP_BUCKET_NAME via /etc/default/n8n-backup or as a cron environment variable.
# Do NOT hard-code the bucket name in this script.
: "${BACKUP_BUCKET_NAME:?BACKUP_BUCKET_NAME must be set (e.g. /etc/default/n8n-backup)}"

TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/var/backups/n8n"
mkdir -p "$BACKUP_DIR"

# Read DB credentials from the tmpfs env file populated by load-secrets.sh.
set -a
source /run/n8n-secrets/.env
set +a

docker compose exec -T postgres \
  pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc \
  > "${BACKUP_DIR}/n8n-${TS}.dump"

aws s3 cp "${BACKUP_DIR}/n8n-${TS}.dump" \
  "s3://${BACKUP_BUCKET_NAME}/n8n/" \
  --storage-class STANDARD_IA

# Retain only 7 days of local copies; S3 lifecycle handles long-term policy.
find "$BACKUP_DIR" -name 'n8n-*.dump' -mtime +7 -delete

echo "Backup complete: ${TS}"
