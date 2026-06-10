#!/usr/bin/env bash
# Issue Let's Encrypt certs for TURN_DOMAIN and install them for coturn.
# Temporarily stops Caddy (port 80) for certbot standalone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$DOCKER_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$DOCKER_DIR/.env"
fi

: "${TURN_DOMAIN:?Set TURN_DOMAIN in .env}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/stealth-server}"

if ! command -v certbot >/dev/null 2>&1; then
  echo "==> Installing certbot"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot
fi

echo "==> Stopping Caddy (frees port 80 for ACME)"
cd "$DEPLOY_DIR"
docker compose stop caddy || true

echo "==> Requesting certificate for $TURN_DOMAIN"
sudo certbot certonly --standalone -d "$TURN_DOMAIN" --non-interactive --agree-tos \
  --register-unsafely-without-email || {
  echo "certbot failed — ensure DNS for $TURN_DOMAIN points to this host." >&2
  docker compose start caddy || true
  exit 1
}

CERT_DIR="/etc/letsencrypt/live/$TURN_DOMAIN"
mkdir -p "$DEPLOY_DIR/coturn/certs"
sudo cp "$CERT_DIR/fullchain.pem" "$DEPLOY_DIR/coturn/certs/fullchain.pem"
sudo cp "$CERT_DIR/privkey.pem" "$DEPLOY_DIR/coturn/certs/privkey.pem"
sudo chown "$(id -u)":"$(id -g)" "$DEPLOY_DIR/coturn/certs/"*.pem

echo "==> Restarting stack"
docker compose up -d

echo ""
echo "TURNS certs installed. Client TURNS_URL example:"
echo "  turns:${TURN_DOMAIN}:5349?transport=tcp"
