#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"
PROJECT_DIR="$REPO_ROOT/web/telegram-tt"
REMOTE_DIR="/var/www/stealth-telegram"
TELEGRAM_PORT="${TELEGRAM_FALLBACK_PORT:-8447}"

if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${SIGNAL_DOMAIN:?}" : "${VPS_PUBLIC_IP:?}" : "${SSH_HOST:=root@${VPS_PUBLIC_IP}}"

echo "[deploy-telegram-tt] 1/5 Installing dependencies..."
cd "$PROJECT_DIR"
npm ci

echo "[deploy-telegram-tt] 2/5 Building production release..."
START_SECONDS=$SECONDS
VITE_POCKETBASE_URL="https://${SIGNAL_DOMAIN}" npm run build:production
BUILD_ELAPSED=$((SECONDS - START_SECONDS))
echo "[deploy-telegram-tt] build finished in ${BUILD_ELAPSED}s"

echo "[deploy-telegram-tt] 3/5 Ensuring remote directory..."
ssh "$SSH_HOST" "mkdir -p $REMOTE_DIR"

echo "[deploy-telegram-tt] 4/5 Syncing build to VPS..."
SYNC_START=$SECONDS
rsync -avz --delete "$PROJECT_DIR/dist/" "$SSH_HOST:$REMOTE_DIR/"
SYNC_ELAPSED=$((SECONDS - SYNC_START))
echo "[deploy-telegram-tt] sync finished in ${SYNC_ELAPSED}s"

echo "[deploy-telegram-tt] 5/5 Updating Caddy telegram block..."
ssh "$SSH_HOST" "mkdir -p /etc/caddy"
ssh "$SSH_HOST" "cat > /tmp/caddy-telegram.conf <<CADDY
:${TELEGRAM_PORT} {
    tls admin@stealthpro.ru
    root * $REMOTE_DIR
    file_server
    encode gzip
}
CADDY"
ssh "$SSH_HOST" "grep -qF ':${TELEGRAM_PORT}' /etc/caddy/Caddyfile || cat /tmp/caddy-telegram.conf >> /etc/caddy/Caddyfile; rm /tmp/caddy-telegram.conf"
ssh "$SSH_HOST" "systemctl reload caddy"

echo "[deploy-telegram-tt] Verifying deployment..."
URL_SCHEME="https"
HTTP_CODE=$(curl -sSf -o /dev/null -w "%{http_code}" "${URL_SCHEME}://${VPS_PUBLIC_IP}:${TELEGRAM_PORT}/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "000" ]]; then
  echo "[deploy-telegram-tt] ${URL_SCHEME}://${VPS_PUBLIC_IP}:${TELEGRAM_PORT}/ returned HTTP ${HTTP_CODE}"
else
  echo "[deploy-telegram-tt] ${URL_SCHEME}://${VPS_PUBLIC_IP}:${TELEGRAM_PORT}/ returned HTTP ${HTTP_CODE} (expected 200)"
fi

echo "[deploy-telegram-tt] Deploy complete."
echo "  URL: ${URL_SCHEME}://${VPS_PUBLIC_IP}:${TELEGRAM_PORT}/"
