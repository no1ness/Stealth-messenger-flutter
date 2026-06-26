#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"
if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${TURN_DOMAIN:?}" : "${VPS_PUBLIC_IP:?}" : "${TURN_USERNAME:?}" : "${TURN_PASSWORD:?}"
: "${VLESS_UUID:?}" "${VLESS_PRIVATE_KEY:?}" "${VLESS_SHORT_ID:?}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/stealth-server}"
mkdir -p "$DEPLOY_DIR"/{pb_data,pb_hooks,coturn/certs,sing-box}
cp "$DOCKER_DIR/docker-compose.yml" "$DEPLOY_DIR/"
cp -a "$REPO_ROOT/server/pb_hooks/." "$DEPLOY_DIR/pb_hooks/"
cp "$DOCKER_DIR/sing-box/config.template.json" "$DEPLOY_DIR/sing-box/"
cp "$DOCKER_DIR/sing-box/entrypoint.sh" "$DEPLOY_DIR/sing-box/"
chmod +x "$DEPLOY_DIR/sing-box/entrypoint.sh"
PB_HOOKS_DIR="${PB_HOOKS_DIR:-$DEPLOY_DIR/pb_hooks}"
if [[ -f "$DEPLOY_DIR/.env" ]]; then
  grep -q '^PB_HOOKS_DIR=' "$DEPLOY_DIR/.env" || printf 'PB_HOOKS_DIR=%s\n' "$PB_HOOKS_DIR" >> "$DEPLOY_DIR/.env"
else
  printf 'PB_HOOKS_DIR=%s\n' "$PB_HOOKS_DIR" > "$DEPLOY_DIR/.env"
fi
export TURN_DOMAIN VPS_PUBLIC_IP TURN_USERNAME TURN_PASSWORD PB_HOOKS_DIR VLESS_UUID VLESS_PRIVATE_KEY VLESS_SHORT_ID
cp "$DOCKER_DIR/Caddyfile.template" "$DEPLOY_DIR/Caddyfile"
envsubst <"$DOCKER_DIR/coturn/turnserver.conf.template" >"$DEPLOY_DIR/coturn/turnserver.conf"
cd "$DEPLOY_DIR" && docker compose pull && docker compose up -d
echo "Stack started in $DEPLOY_DIR
INFO [caddy] API on :8443, web on ${WEB_FALLBACK_PORT:-8445} (${WEB_DOMAIN:-app.stealthpro.ru}), dashboard on ${DASHBOARD_FALLBACK_PORT:-8446} (${DASHBOARD_DOMAIN:-dashboard.stealthpro.ru})
INFO [caddy] port 443 released to sing-box"
