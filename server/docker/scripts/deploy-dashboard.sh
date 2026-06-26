#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"
if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${VPS_PUBLIC_IP:?Must set VPS_PUBLIC_IP in .env}"
: "${DASHBOARD_FALLBACK_PORT:=8446}"
: "${SSH_HOST:=root@${VPS_PUBLIC_IP}}"
: "${DASHBOARD_DOMAIN:=dashboard.stealthpro.ru}"

echo "[deploy-dashboard] 1/6 Ensuring remote directory..."
ssh "$SSH_HOST" "mkdir -p /opt/stealth-dashboard"

echo "[deploy-dashboard] 2/6 Syncing dashboard-server to VPS..."
SYNC_START=$SECONDS
rsync -avz --delete "$REPO_ROOT/pw-test/dashboard-server/" "$SSH_HOST:/opt/stealth-dashboard/"
SYNC_ELAPSED=$((SECONDS - SYNC_START))
echo "[deploy-dashboard] sync finished in ${SYNC_ELAPSED}s"

echo "[deploy-dashboard] 3/6 Installing pm2 (if needed)..."
ssh "$SSH_HOST" "command -v pm2 &>/dev/null || npm install -g pm2"

echo "[deploy-dashboard] 4/6 Starting/restarting dashboard via pm2..."
ssh "$SSH_HOST" "cd /opt/stealth-dashboard && DASHBOARD_PORT=3001 STEALTH_POCKETBASE_URL=http://127.0.0.1:8443 pm2 start index.js --name stealth-dashboard -- --port 3001 2>/dev/null || pm2 restart stealth-dashboard"
ssh "$SSH_HOST" "pm2 save"

echo "[deploy-dashboard] 5/6 Configuring Caddy reverse proxy for ${DASHBOARD_DOMAIN}..."
TLS_BLOCK="# tls — set DNS_API_TOKEN in .env for automatic HTTPS"
if [[ -n "${DNS_API_TOKEN:-}" ]]; then
  ssh "$SSH_HOST" "WEB_DOMAIN='${DASHBOARD_DOMAIN}' DNS_API_TOKEN='${DNS_API_TOKEN}' bash -s" < "$SCRIPT_DIR/ensure-web-cert.sh"
  TLS_BLOCK="tls /etc/letsencrypt/live/${DASHBOARD_DOMAIN}/fullchain.pem /etc/letsencrypt/live/${DASHBOARD_DOMAIN}/privkey.pem"
  URL_SCHEME="https"
else
  echo "[deploy-dashboard] WARNING: DNS_API_TOKEN not set — deploying without TLS"
  URL_SCHEME="http"
fi

ssh "$SSH_HOST" "mkdir -p /etc/caddy"
ssh "$SSH_HOST" "cat > /tmp/caddy-dashboard.conf <<CADDY
${DASHBOARD_DOMAIN}:${DASHBOARD_FALLBACK_PORT} {
    ${TLS_BLOCK}
    reverse_proxy 127.0.0.1:3001
    encode gzip
}
CADDY"
ssh "$SSH_HOST" "grep -qF '${DASHBOARD_DOMAIN}' /etc/caddy/Caddyfile || cat /tmp/caddy-dashboard.conf >> /etc/caddy/Caddyfile; rm /tmp/caddy-dashboard.conf"
ssh "$SSH_HOST" "systemctl reload caddy"

echo "[deploy-dashboard] 6/6 Verifying deployment..."
HTTP_CODE=$(curl -sSf -o /dev/null -w "%{http_code}" "http://${VPS_PUBLIC_IP}:${DASHBOARD_FALLBACK_PORT}/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "000" ]]; then
  echo "[deploy-dashboard] http://${VPS_PUBLIC_IP}:${DASHBOARD_FALLBACK_PORT}/ returned HTTP ${HTTP_CODE}"
else
  echo "[deploy-dashboard] http://${VPS_PUBLIC_IP}:${DASHBOARD_FALLBACK_PORT}/ returned HTTP ${HTTP_CODE} (expected 200)"
fi

echo "[deploy-dashboard] Deploy complete."
echo "  URL: ${URL_SCHEME}://${DASHBOARD_DOMAIN}/"
echo "  Fallback: http://${VPS_PUBLIC_IP}:${DASHBOARD_FALLBACK_PORT}/"
