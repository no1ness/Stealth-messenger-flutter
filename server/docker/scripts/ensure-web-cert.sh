#!/usr/bin/env bash
# Obtains/renews a Let's Encrypt certificate for the web domain
# using certbot DNS-01 challenge.
#
# Prerequisites:
#   - certbot installed
#   - DNS_API_TOKEN set in .env (Cloudflare API token with
#     DNS:Edit permission for the zone)
#   - certbot-dns-cloudflare plugin installed
#
# Usage:
#   export WEB_DOMAIN=app.stealthpro.ru
#   export DNS_API_TOKEN=your_cloudflare_token
#   ./ensure-web-cert.sh

set -euo pipefail

: "${WEB_DOMAIN:?}" "${DNS_API_TOKEN:?}"

CERT_DIR="/etc/letsencrypt/live/${WEB_DOMAIN}"

# Already issued and valid (>30 days remaining)?
if [[ -f "${CERT_DIR}/fullchain.pem" ]]; then
  EXPIRY=$(openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -enddate 2>/dev/null \
    | cut -d= -f2)
  if [[ -n "$EXPIRY" ]]; then
    REMAINING=$(( ($(date -d "$EXPIRY" +%s) - $(date +%s)) / 86400 ))
    if [[ $REMAINING -gt 30 ]]; then
      echo "[ensure-web-cert] cert valid for ${REMAINING}d, skipping"
      exit 0
    fi
    echo "[ensure-web-cert] cert expires in ${REMAINING}d, renewing"
  fi
fi

# Write Cloudflare credentials for certbot
mkdir -p /etc/letsencrypt
cat > /etc/letsencrypt/cloudflare.ini <<CFINI
# Cloudflare API token for certbot DNS-01 (auto-generated)
dns_cloudflare_api_token = ${DNS_API_TOKEN}
CFINI
chmod 600 /etc/letsencrypt/cloudflare.ini

certbot certonly \
  --non-interactive \
  --agree-tos \
  --email "admin@${WEB_DOMAIN}" \
  --preferred-challenges dns \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --domains "${WEB_DOMAIN}" \
  --deploy-hook "systemctl reload caddy || true"

echo "[ensure-web-cert] certificate obtained for ${WEB_DOMAIN}"
ls -la "${CERT_DIR}/"
