#!/usr/bin/env bash
# Update the server to the newest code: pull, rebuild, restart, check. Data (database, uploads) stays.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
BRANCH="${1:-main}"
git -C .. fetch origin "$BRANCH"
git -C .. checkout "$BRANCH"
git -C .. pull --ff-only origin "$BRANCH"
# A copy of the database first: the new code may change tables.
./backup.sh
docker compose up -d --build
set -a; . ./.env; set +a
for i in $(seq 1 40); do
  if curl -fsS "https://$API_DOMAIN/health" >/dev/null 2>&1; then echo "Updated: https://$API_DOMAIN/health answers."; docker image prune -f >/dev/null; exit 0; fi
  sleep 5
done
echo "The backend does not answer yet: docker compose logs --tail=100 backend"; exit 1
