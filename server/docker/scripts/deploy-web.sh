#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"
if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${SIGNAL_DOMAIN:?}" : "${VPS_PUBLIC_IP:?}"
: "${WEB_DOMAIN:=app.${SIGNAL_DOMAIN#signal.}}"
: "${SSH_HOST:=root@${VPS_PUBLIC_IP}}"

echo "[deploy-web] 1/5 Building web release..."
START_SECONDS=$SECONDS
"$SCRIPT_DIR/build-client-web.sh"
BUILD_ELAPSED=$((SECONDS - START_SECONDS))
echo "[deploy-web] build finished in ${BUILD_ELAPSED}s"

echo "[deploy-web] 2/5 Syncing web launcher (landing page) to VPS root..."
ssh "$SSH_HOST" "mkdir -p /var/www/stealth-web"

SYNC_LAUNCHER_START=$SECONDS
rsync -avz --delete "$REPO_ROOT/server/docker/web-launcher/" "$SSH_HOST:/var/www/stealth-web/"
SYNC_LAUNCHER_ELAPSED=$((SECONDS - SYNC_LAUNCHER_START))
echo "[deploy-web] launcher sync finished in ${SYNC_LAUNCHER_ELAPSED}s"

echo "[deploy-web] 3/5 Syncing Flutter web build to /stealth/ subdirectory..."
ssh "$SSH_HOST" "mkdir -p /var/www/stealth-web/stealth"

SYNC_START=$SECONDS
rsync -avz --delete "$REPO_ROOT/client/build/web/" "$SSH_HOST:/var/www/stealth-web/stealth/"
SYNC_ELAPSED=$((SECONDS - SYNC_START))
echo "[deploy-web] Flutter build sync finished in ${SYNC_ELAPSED}s"

echo "[deploy-web] 4/5 Ensuring TLS certificate..."
WEB_PORT="${WEB_FALLBACK_PORT:-8445}"
if [[ -n "${DNS_API_TOKEN:-}" ]]; then
  ssh "$SSH_HOST" "WEB_DOMAIN='${WEB_DOMAIN}' DNS_API_TOKEN='${DNS_API_TOKEN}' bash -s" < "$SCRIPT_DIR/ensure-web-cert.sh"
  TLS_BLOCK="tls /etc/letsencrypt/live/${WEB_DOMAIN}/fullchain.pem /etc/letsencrypt/live/${WEB_DOMAIN}/privkey.pem"
  URL_SCHEME="https"
else
  echo "[deploy-web] ⚠️  DNS_API_TOKEN not set — deploying without TLS"
  TLS_BLOCK="# tls — set DNS_API_TOKEN in .env for automatic HTTPS"
  URL_SCHEME="http"
fi

echo "[deploy-web] 5/5 Updating Caddy web block..."
ssh "$SSH_HOST" "mkdir -p /etc/caddy"
ssh "$SSH_HOST" "cat > /tmp/caddy-web.conf <<CADDY
:${WEB_PORT} {
    ${TLS_BLOCK}
    root * /var/www/stealth-web
    file_server
    encode gzip
}
CADDY"
ssh "$SSH_HOST" "grep -qF ':${WEB_PORT}' /etc/caddy/Caddyfile || cat /tmp/caddy-web.conf >> /etc/caddy/Caddyfile; rm /tmp/caddy-web.conf"
ssh "$SSH_HOST" "systemctl reload caddy"

echo "[deploy-web] 6/6 Verifying deployment..."
HTTP_CODE=$(curl -sSf -o /dev/null -w "%{http_code}" "${URL_SCHEME}://${VPS_PUBLIC_IP}:${WEB_PORT}/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "000" ]]; then
  echo "[deploy-web] ✅ ${URL_SCHEME}://${VPS_PUBLIC_IP}:${WEB_PORT}/ returned HTTP ${HTTP_CODE}"
else
  echo "[deploy-web] ⚠️  ${URL_SCHEME}://${VPS_PUBLIC_IP}:${WEB_PORT}/ returned HTTP ${HTTP_CODE} (expected 200)"
fi

echo "[deploy-web] Deploy complete."
echo "  URL: ${URL_SCHEME}://${VPS_PUBLIC_IP}:${WEB_PORT}/"
