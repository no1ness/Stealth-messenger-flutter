#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"
if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${SIGNAL_DOMAIN:?}" : "${TURN_DOMAIN:?}" : "${VPS_PUBLIC_IP:?}" : "${TURN_USERNAME:?}" : "${TURN_PASSWORD:?}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/stealth-server}"
mkdir -p "$DEPLOY_DIR"/{pb_data,pb_hooks,coturn/certs}
cp "$DOCKER_DIR/docker-compose.yml" "$DEPLOY_DIR/"
cp -a "$REPO_ROOT/server/pb_hooks/." "$DEPLOY_DIR/pb_hooks/"
PB_HOOKS_DIR="${PB_HOOKS_DIR:-$DEPLOY_DIR/pb_hooks}"
if [[ -f "$DEPLOY_DIR/.env" ]]; then
  grep -q '^PB_HOOKS_DIR=' "$DEPLOY_DIR/.env" || printf 'PB_HOOKS_DIR=%s\n' "$PB_HOOKS_DIR" >> "$DEPLOY_DIR/.env"
else
  printf 'PB_HOOKS_DIR=%s\n' "$PB_HOOKS_DIR" > "$DEPLOY_DIR/.env"
fi
export SIGNAL_DOMAIN TURN_DOMAIN VPS_PUBLIC_IP TURN_USERNAME TURN_PASSWORD PB_HOOKS_DIR
envsubst <"$DOCKER_DIR/Caddyfile.template" >"$DEPLOY_DIR/Caddyfile"
envsubst <"$DOCKER_DIR/coturn/turnserver.conf.template" >"$DEPLOY_DIR/coturn/turnserver.conf"
cd "$DEPLOY_DIR" && docker compose pull && docker compose up -d
echo "Stack started in $DEPLOY_DIR"
