#!/usr/bin/env bash
# Let's Encrypt for turn.stealthpro.ru → coturn/certs/
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${TURN_DOMAIN:?Set TURN_DOMAIN in .env}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/stealth-server}"
if ! command -v certbot >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot
fi
cd "$DEPLOY_DIR"
docker compose stop caddy || true
sudo certbot certonly --standalone -d "$TURN_DOMAIN" --non-interactive --agree-tos \
  --register-unsafely-without-email || {
  docker compose start caddy || true
  exit 1
}
CERT_DIR="/etc/letsencrypt/live/$TURN_DOMAIN"
mkdir -p "$DEPLOY_DIR/coturn/certs"
sudo cp "$CERT_DIR/fullchain.pem" "$DEPLOY_DIR/coturn/certs/fullchain.pem"
sudo cp "$CERT_DIR/privkey.pem" "$DEPLOY_DIR/coturn/certs/privkey.pem"
sudo chown "$(id -u)":"$(id -g)" "$DEPLOY_DIR/coturn/certs/"*.pem
docker compose up -d
echo "TURNS certs installed for $TURN_DOMAIN"
