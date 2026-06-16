#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"
if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${VPS_PUBLIC_IP:?}"
: "${DASHBOARD_FALLBACK_PORT:=8446}"
: "${SSH_HOST:=root@${VPS_PUBLIC_IP}}"

echo "[deploy-dashboard] 1/5 Building dashboard release..."
START_SECONDS=$SECONDS
"$SCRIPT_DIR/build-client-dashboard.sh"
BUILD_ELAPSED=$((SECONDS - START_SECONDS))
echo "[deploy-dashboard] build finished in ${BUILD_ELAPSED}s"

echo "[deploy-dashboard] 2/5 Ensuring remote directory..."
ssh "$SSH_HOST" "mkdir -p /var/www/stealth-dashboard"

echo "[deploy-dashboard] 3/5 Syncing build to VPS..."
SYNC_START=$SECONDS
rsync -avz --delete "$REPO_ROOT/client/build/dashboard/" "$SSH_HOST:/var/www/stealth-dashboard/"
SYNC_ELAPSED=$((SECONDS - SYNC_START))
echo "[deploy-dashboard] sync finished in ${SYNC_ELAPSED}s"

echo "[deploy-dashboard] 4/5 Updating Caddy dashboard block..."
ssh "$SSH_HOST" "mkdir -p /etc/caddy"
ssh "$SSH_HOST" "cat > /tmp/caddy-dashboard.conf <<CADDY
:${DASHBOARD_FALLBACK_PORT} {
    root * /var/www/stealth-dashboard
    file_server
    encode gzip
}
CADDY"
ssh "$SSH_HOST" "grep -qF ':${DASHBOARD_FALLBACK_PORT}' /etc/caddy/Caddyfile || cat /tmp/caddy-dashboard.conf >> /etc/caddy/Caddyfile; rm /tmp/caddy-dashboard.conf"
ssh "$SSH_HOST" "systemctl reload caddy"

echo "[deploy-dashboard] 5/5 Verifying deployment..."
HTTP_CODE=$(curl -sSf -o /dev/null -w "%{http_code}" "http://${VPS_PUBLIC_IP}:${DASHBOARD_FALLBACK_PORT}/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "000" ]]; then
  echo "[deploy-dashboard] http://${VPS_PUBLIC_IP}:${DASHBOARD_FALLBACK_PORT}/ returned HTTP ${HTTP_CODE}"
else
  echo "[deploy-dashboard] http://${VPS_PUBLIC_IP}:${DASHBOARD_FALLBACK_PORT}/ returned HTTP ${HTTP_CODE} (expected 200)"
fi

echo "[deploy-dashboard] Deploy complete."
echo "  URL: http://${VPS_PUBLIC_IP}:${DASHBOARD_FALLBACK_PORT}/"
