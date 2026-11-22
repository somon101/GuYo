#!/usr/bin/env bash
# Put a database copy back:  bash deploy/restore.sh deploy/backups/guyo-2026-11-23-0217.sql.gz
# It REPLACES the current database. Stop and think before running it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
FILE="${1:?Usage: restore.sh path/to/guyo-....sql.gz}"
read -r -p "This replaces the whole database with $FILE. Type YES to go on: " OK
[ "$OK" = "YES" ] || { echo "Cancelled."; exit 1; }
docker compose stop backend
docker compose exec -T db psql -U guyo -d postgres -c "DROP DATABASE IF EXISTS guyo WITH (FORCE);" -c "CREATE DATABASE guyo OWNER guyo;"
gunzip -c "$FILE" | docker compose exec -T db psql -U guyo -d guyo
docker compose up -d backend
echo "Restored."
