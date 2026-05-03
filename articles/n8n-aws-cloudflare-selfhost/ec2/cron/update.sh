#!/bin/bash
# Weekly n8n image update. Install via cron entry such as:
#   0 4 * * 0 /opt/n8n/cron/update.sh >> /var/log/n8n-update.log 2>&1

set -euo pipefail
cd /opt/n8n

# Take a backup first so we can roll back if the new image misbehaves.
/opt/n8n/cron/backup.sh

# Reload secrets into the env so docker compose can resolve interpolated values.
set -a
source /run/n8n-secrets/.env
set +a

docker compose pull
docker compose up -d
docker image prune -f
