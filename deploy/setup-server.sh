#!/usr/bin/env bash
# One-time setup of a fresh Ubuntu 22.04/24.04 server (run as root) and the first start of GuYo.
#
#   curl/clone the repository to /opt/guyo, then:
#   sudo bash /opt/guyo/deploy/setup-server.sh api.your-domain.com [admin-password]
#
# What it does (safe to run again): 2 GB swap (the server is small), a firewall (22, 80, 443 only),
# automatic security updates, Docker, the .env with random secrets, the first start, a nightly backup.
set -euo pipefail

DOMAIN="${1:-}"
ADMIN_PASSWORD="${2:-}"
if [ -z "$DOMAIN" ]; then
  echo "Usage: bash deploy/setup-server.sh api.your-domain.com [admin-password]"; exit 1
fi
if [ "$(id -u)" -ne 0 ]; then echo "Run as root (sudo)."; exit 1; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "== 1/7 Swap =="
if ! swapon --show | grep -q .; then
  fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
sysctl -w vm.swappiness=10 >/dev/null
grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf

echo "== 2/7 Packages =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl ufw unattended-upgrades gzip cron openssl
if ! command -v docker >/dev/null 2>&1; then curl -fsSL https://get.docker.com | sh; fi
systemctl enable --now docker

echo "== 3/7 Firewall =="
ufw allow 22/tcp >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

echo "== 4/7 Automatic security updates =="
dpkg-reconfigure -f noninteractive unattended-upgrades || true

echo "== 5/7 Settings (.env) =="
if [ ! -f .env ]; then
  cp .env.example .env
  rand() { openssl rand -base64 36 | tr -d '/+=\n' | cut -c1-40; }
  [ -n "$ADMIN_PASSWORD" ] || ADMIN_PASSWORD="$(rand)"
  sed -i "s|^API_DOMAIN=.*|API_DOMAIN=$DOMAIN|" .env
  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$(rand)|" .env
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(rand)|" .env
  sed -i "s|^SEED_ADMIN_PASSWORD=.*|SEED_ADMIN_PASSWORD=$ADMIN_PASSWORD|" .env
  chmod 600 .env
  echo "Created deploy/.env with fresh random secrets."
  echo ">>> Admin login: admin   password: $ADMIN_PASSWORD   (write it down, change it in the panel)"
else
  echo "deploy/.env exists, kept as it is."
fi

echo "== 6/7 First start (the build takes a few minutes) =="
mkdir -p data/postgres data/storage backups
docker compose up -d --build
echo "Waiting for the backend..."
for i in $(seq 1 60); do
  if curl -fsS "https://$DOMAIN/health" >/dev/null 2>&1; then echo "Backend answers: https://$DOMAIN/health"; break; fi
  sleep 5
  if [ "$i" -eq 60 ]; then echo "Not answering yet. Check: docker compose logs --tail=100 backend caddy (is the domain pointing at this server?)"; fi
done

echo "== 7/7 Nightly backup =="
chmod +x backup.sh restore.sh update.sh
CRON="17 21 * * * root $HERE/backup.sh >> $HERE/backups/backup.log 2>&1"
echo "$CRON" > /etc/cron.d/guyo-backup
chmod 644 /etc/cron.d/guyo-backup

echo
echo "Done. API: https://$DOMAIN   Admin panel: opens from GitHub Pages (its API address must be https://$DOMAIN)."
echo "Update later with: bash $HERE/update.sh"
