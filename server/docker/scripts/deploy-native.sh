#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"

if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${SIGNAL_DOMAIN:?}" : "${TURN_DOMAIN:?}" : "${VPS_PUBLIC_IP:?}" : "${TURN_USERNAME:?}" : "${TURN_PASSWORD:?}"
: "${WEB_DOMAIN:=app.${SIGNAL_DOMAIN#signal.}}"

export SIGNAL_DOMAIN TURN_DOMAIN VPS_PUBLIC_IP TURN_USERNAME TURN_PASSWORD WEB_DOMAIN

# --- install system packages ---
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl wget unzip caddy coturn certbot

systemctl disable --now coturn 2>/dev/null || true  # we manage it manually

# --- PocketBase binary ---
PB_VERSION=0.23.0
PB_DIR=/opt/pocketbase
mkdir -p "$PB_DIR/pb_data" "$PB_DIR/pb_hooks"
cp -a "$REPO_ROOT/server/pb_hooks/." "$PB_DIR/pb_hooks/"

if [[ ! -f "$PB_DIR/pocketbase" ]]; then
  wget -qO /tmp/pb.zip "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip"
  unzip -qo /tmp/pb.zip -d "$PB_DIR"
  rm /tmp/pb.zip
  chmod +x "$PB_DIR/pocketbase"
fi

cat > /etc/systemd/system/pocketbase.service <<UNIT
[Unit]
Description=PocketBase
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PB_DIR
ExecStart=$PB_DIR/pocketbase serve --http=0.0.0.0:8090 --dir=$PB_DIR/pb_data --hooksDir=$PB_DIR/pb_hooks
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# --- web app directory ---
mkdir -p /var/www/stealth-web

# --- Caddy config ---
mkdir -p /etc/caddy
cat > /etc/caddy/Caddyfile <<CADDY
${SIGNAL_DOMAIN} {
    reverse_proxy localhost:8090
}

${WEB_DOMAIN} {
    root * /var/www/stealth-web
    file_server
    encode gzip
}
CADDY

systemctl enable --now caddy

# --- coturn config ---
cat > /etc/turnserver.conf <<TURN
listening-port=3478
tls-listening-port=5349
external-ip=${VPS_PUBLIC_IP}
realm=${TURN_DOMAIN}
server-name=${TURN_DOMAIN}

fingerprint
lt-cred-mech
user=${TURN_USERNAME}:${TURN_PASSWORD}

min-port=49152
max-port=65535
no-cli
no-tlsv1
no-tlsv1_1

cert=/etc/letsencrypt/live/${TURN_DOMAIN}/fullchain.pem
pkey=/etc/letsencrypt/live/${TURN_DOMAIN}/privkey.pem
TURN

cat > /etc/systemd/system/coturn.service <<UNIT
[Unit]
Description=coturn TURN server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/turnserver -c /etc/turnserver.conf
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now pocketbase
systemctl enable --now coturn

echo "=== Web app dir ==="
ls -la /var/www/stealth-web 2>/dev/null || echo "(empty — deploy web build later)"

echo "=== All services started ==="
systemctl status pocketbase caddy coturn --no-pager
