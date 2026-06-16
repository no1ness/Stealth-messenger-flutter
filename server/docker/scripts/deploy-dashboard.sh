#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"
if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${SIGNAL_DOMAIN:?}" : "${VPS_PUBLIC_IP:?}"
: "${DASHBOARD_DOMAIN:=dashboard.${SIGNAL_DOMAIN#signal.}}"
: "${WEB_DOMAIN:=app.${SIGNAL_DOMAIN#signal.}}"
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

echo "[deploy-dashboard] 4/5 Updating Caddy config..."
ssh "$SSH_HOST" "mkdir -p /etc/caddy"

# Read current Caddyfile, append dashboard block, write back.
# We use a temp file to avoid heredoc shell escaping issues.
ssh "$SSH_HOST" "cat > /etc/caddy/Caddyfile <<'CADDY'
${SIGNAL_DOMAIN} {
    reverse_proxy localhost:8090
}

${WEB_DOMAIN} {
    root * /var/www/stealth-web
    file_server
    encode gzip
}

${DASHBOARD_DOMAIN} {
    root * /var/www/stealth-dashboard
    file_server
    encode gzip
}
CADDY"
ssh "$SSH_HOST" "systemctl reload caddy"

echo "[deploy-dashboard] 5/5 Verifying deployment..."
HTTP_CODE=$(curl -sSf -o /dev/null -w "%{http_code}" "https://${DASHBOARD_DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "000" ]]; then
  echo "[deploy-dashboard] https://${DASHBOARD_DOMAIN}/ returned HTTP ${HTTP_CODE}"
else
  echo "[deploy-dashboard] https://${DASHBOARD_DOMAIN}/ returned HTTP ${HTTP_CODE} (expected 200)"
fi

echo "[deploy-dashboard] Deploy complete."
echo "  URL: https://${DASHBOARD_DOMAIN}/"
