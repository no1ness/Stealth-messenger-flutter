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

echo "[deploy-web] 2/5 Ensuring remote directory..."
ssh "$SSH_HOST" "mkdir -p /var/www/stealth-web"

echo "[deploy-web] 3/5 Syncing build to VPS..."
SYNC_START=$SECONDS
rsync -avz --delete "$REPO_ROOT/client/build/web/" "$SSH_HOST:/var/www/stealth-web/"
SYNC_ELAPSED=$((SECONDS - SYNC_START))
echo "[deploy-web] sync finished in ${SYNC_ELAPSED}s"

echo "[deploy-web] 4/5 Updating Caddy config..."
ssh "$SSH_HOST" "mkdir -p /etc/caddy"
ssh "$SSH_HOST" "cat > /etc/caddy/Caddyfile <<'CADDY'
${SIGNAL_DOMAIN} {
    reverse_proxy localhost:8090
}

${WEB_DOMAIN} {
    root * /var/www/stealth-web
    file_server
    encode gzip
}
CADDY"
ssh "$SSH_HOST" "systemctl reload caddy"

echo "[deploy-web] 5/5 Verifying deployment..."
HTTP_CODE=$(curl -sSf -o /dev/null -w "%{http_code}" "https://${WEB_DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "000" ]]; then
  echo "[deploy-web] ✅ https://${WEB_DOMAIN}/ returned HTTP ${HTTP_CODE}"
else
  echo "[deploy-web] ⚠️  https://${WEB_DOMAIN}/ returned HTTP ${HTTP_CODE} (expected 200)"
fi

echo "[deploy-web] Deploy complete."
echo "  URL: https://${WEB_DOMAIN}/"
