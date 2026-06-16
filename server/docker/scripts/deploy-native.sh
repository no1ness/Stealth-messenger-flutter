#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"

if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${TURN_DOMAIN:?}" : "${VPS_PUBLIC_IP:?}" : "${TURN_USERNAME:?}" : "${TURN_PASSWORD:?}"
: "${WEB_FALLBACK_PORT:=8445}" : "${DASHBOARD_FALLBACK_PORT:=8446}"

export TURN_DOMAIN VPS_PUBLIC_IP TURN_USERNAME TURN_PASSWORD WEB_FALLBACK_PORT DASHBOARD_FALLBACK_PORT

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

# --- Caddy config (on fallback ports — 443 is owned by sing-box) ---
mkdir -p /etc/caddy
cat > /etc/caddy/Caddyfile <<CADDY
:8443 {
    reverse_proxy localhost:8090
}

:${WEB_FALLBACK_PORT} {
    root * /var/www/stealth-web
    file_server
    encode gzip
}

:${DASHBOARD_FALLBACK_PORT} {
    root * /var/www/stealth-dashboard
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

# --- sing-box binary (native) ---
SING_BOX_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')
wget -qO /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-amd64.tar.gz"
tar -xzf /tmp/sing-box.tar.gz -C /tmp/
cp "/tmp/sing-box-${SING_BOX_VERSION}-linux-amd64/sing-box" /usr/local/bin/sing-box
chmod +x /usr/local/bin/sing-box
rm -rf /tmp/sing-box*

mkdir -p /etc/sing-box
cp "$REPO_ROOT/server/docker/sing-box/config.template.json" /etc/sing-box/config.template.json

cat > /etc/systemd/system/sing-box.service <<UNIT
[Unit]
Description=Sing-box VLESS-Reality
After=network.target
[Service]
Type=simple
Environment=VLESS_UUID=${VLESS_UUID}
Environment=VLESS_PRIVATE_KEY=${VLESS_PRIVATE_KEY}
Environment=VLESS_SHORT_ID=${VLESS_SHORT_ID}
ExecStart=/bin/sh -c 'sed -e "s|\${VLESS_UUID}|$VLESS_UUID|g" -e "s|\${VLESS_PRIVATE_KEY}|$VLESS_PRIVATE_KEY|g" -e "s|\${VLESS_SHORT_ID}|$VLESS_SHORT_ID|g" /etc/sing-box/config.template.json > /etc/sing-box/config.json && exec /usr/local/bin/sing-box run -c /etc/sing-box/config.json'
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now pocketbase
systemctl enable --now coturn
systemctl enable --now sing-box

echo "=== Web app dir ==="
ls -la /var/www/stealth-web 2>/dev/null || echo "(empty — deploy web build later)"

echo "=== All services started ==="
systemctl status pocketbase caddy coturn sing-box --no-pager
