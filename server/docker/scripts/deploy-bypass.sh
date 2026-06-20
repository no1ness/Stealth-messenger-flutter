#!/usr/bin/env bash
set -euo pipefail

SING_BOX_VERSION=1.10.7

# 1. Download sing-box v1.10 (supports override_address/override_port)
echo "=== Downloading sing-box v$SING_BOX_VERSION ==="
wget -qO /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-amd64.tar.gz"
tar -xzf /tmp/sing-box.tar.gz -C /tmp/
cp "/tmp/sing-box-${SING_BOX_VERSION}-linux-amd64/sing-box" /usr/local/bin/sing-box
chmod +x /usr/local/bin/sing-box
rm -rf /tmp/sing-box*
echo "sing-box $(sing-box version | head -1)"

# 2. Setup sing-box systemd service
echo '=== Creating systemd service ==='
cat > /etc/systemd/system/sing-box.service << 'SERVICE'
[Unit]
Description=Sing-box VLESS-Reality
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

# 3. Generate config.json from template
sed -e 's/${VLESS_UUID}/8b07efcf-cf87-42e8-b9d6-dd0d6b8618b3/g' \
    -e 's/${VLESS_PRIVATE_KEY}/yCmvJauu9n9-Vhvy2Jyj0LYOX4cSAAw0Ne0KiIUXs3Y/g' \
    -e 's/${VLESS_SHORT_ID}/8471221de9b86ec1/g' \
    /etc/sing-box/config.template.json > /etc/sing-box/config.json

echo '=== Config ==='
cat /etc/sing-box/config.json

# 4. Reconfigure Caddy to use port 8443 (free port 443 for sing-box)
echo '=== Reconfiguring Caddy ==='
# Current Caddyfile has no ports - Caddy listens on 443 automatically
# Create new Caddyfile with explicit ports
WEB_DOMAIN="${WEB_DOMAIN:-app.stealthpro.ru}"
DNS_API_TOKEN="${DNS_API_TOKEN:-}"

if [[ -n "$DNS_API_TOKEN" ]]; then
  echo "[deploy-bypass] Obtaining TLS cert for ${WEB_DOMAIN}..."
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WEB_DOMAIN="$WEB_DOMAIN" DNS_API_TOKEN="$DNS_API_TOKEN" bash "$SCRIPT_DIR/ensure-web-cert.sh"
  WEB_TLS="tls /etc/letsencrypt/live/${WEB_DOMAIN}/fullchain.pem /etc/letsencrypt/live/${WEB_DOMAIN}/privkey.pem"
else
  echo "[deploy-bypass] ⚠️  DNS_API_TOKEN not set — deploying without TLS"
  WEB_TLS="# tls — set DNS_API_TOKEN in .env for HTTPS"
fi

cat > /etc/caddy/Caddyfile <<CADDY
:8443 {
    reverse_proxy localhost:8090
}

:8445 {
    ${WEB_TLS}
    root * /var/www/stealth-web
    file_server
    encode gzip
}

:8446 {
    root * /var/www/stealth-dashboard
    file_server
    encode gzip
}
CADDY

# Reload Caddy
systemctl stop caddy 2>/dev/null || true
systemctl start caddy 2>/dev/null || true
sleep 1

# 5. Start sing-box
systemctl daemon-reload
systemctl enable --now sing-box
sleep 2

# 6. Verify
echo '=== Service status ==='
systemctl status sing-box --no-pager 2>&1 | head -10

echo '=== Ports ==='
ss -tlnp | grep -E '443|8443|8090|3478|5349'

echo '=== Health check ==='
curl -s -o /dev/null -w "Caddy 8443: %{http_code}\n" http://localhost:8443/api/health 2>/dev/null || echo "caddy health failed"
