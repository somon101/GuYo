#!/usr/bin/env bash
# A compressed copy of the database (and the uploaded files) into deploy/backups, the last 7 days kept.
# IMPORTANT: this is the same disk as the server. Copy deploy/backups somewhere else too (another
# server or a cloud disk): see docs/DEPLOY.md, «Копии базы».
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
mkdir -p backups
STAMP="$(date +%F-%H%M)"
docker compose exec -T db pg_dump -U guyo -d guyo --no-owner | gzip -9 > "backups/guyo-$STAMP.sql.gz"
tar -czf "backups/storage-$STAMP.tar.gz" -C data storage 2>/dev/null || true
find backups -name 'guyo-*.sql.gz' -mtime +7 -delete
find backups -name 'storage-*.tar.gz' -mtime +7 -delete
echo "$(date -Is) backup ok: backups/guyo-$STAMP.sql.gz ($(du -h "backups/guyo-$STAMP.sql.gz" | cut -f1))"
