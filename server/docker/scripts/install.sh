#!/usr/bin/env bash
# Materialize configs and start PocketBase + Caddy + coturn on the VPS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_SERVER_DIR="$(cd "$DOCKER_DIR/.." && pwd)"

if [[ -f "$DOCKER_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$DOCKER_DIR/.env"
else
  echo "Missing $DOCKER_DIR/.env — copy from .env.example and edit." >&2
  exit 1
fi

: "${SIGNAL_DOMAIN:?}"
: "${TURN_DOMAIN:?}"
: "${VPS_PUBLIC_IP:?}"
: "${TURN_USERNAME:?}"
: "${TURN_PASSWORD:?}"

DEPLOY_DIR="${DEPLOY_DIR:-$HOME/stealth-server}"

echo "==> Deploy directory: $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"/{pb_data,pb_hooks,coturn/certs}

echo "==> Copying docker-compose and hooks"
cp "$DOCKER_DIR/docker-compose.yml" "$DEPLOY_DIR/"
cp -a "$REPO_SERVER_DIR/pb_hooks/." "$DEPLOY_DIR/pb_hooks/"

echo "==> Rendering Caddyfile and coturn config"
export SIGNAL_DOMAIN TURN_DOMAIN VPS_PUBLIC_IP TURN_USERNAME TURN_PASSWORD
envsubst <"$DOCKER_DIR/Caddyfile.template" >"$DEPLOY_DIR/Caddyfile"
envsubst <"$DOCKER_DIR/coturn/turnserver.conf.template" >"$DEPLOY_DIR/coturn/turnserver.conf"

if [[ ! -f "$DEPLOY_DIR/coturn/certs/fullchain.pem" ]]; then
  echo ""
  echo "WARNING: $DEPLOY_DIR/coturn/certs/fullchain.pem not found."
  echo "TURNS (5349) will fail until you run: ./scripts/issue-turn-certs.sh"
  echo "TURN on 3478 can still work without TLS certs."
  echo ""
fi

cd "$DEPLOY_DIR"
docker compose pull
docker compose up -d

echo ""
echo "Stack started in $DEPLOY_DIR"
echo ""
echo "Next steps:"
echo "  1. docker compose -f $DEPLOY_DIR/docker-compose.yml logs -f pocketbase"
echo "     Create admin at https://${SIGNAL_DOMAIN}/_/"
echo "  2. Import rtc_signaling (after admin exists):"
echo "     POCKETBASE_URL=https://${SIGNAL_DOMAIN} \\"
echo "       POCKETBASE_ADMIN_EMAIL=... POCKETBASE_ADMIN_PASSWORD=... \\"
echo "       $DOCKER_DIR/scripts/import-rtc-signaling.sh"
echo "  3. docker compose -f $DEPLOY_DIR/docker-compose.yml restart pocketbase"
echo "  4. ./scripts/issue-turn-certs.sh  (if not done)"
echo "  5. ./scripts/verify-signaling.sh"
