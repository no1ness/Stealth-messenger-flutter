#!/bin/sh
# sed delimiter | avoids conflict with base64 (/) in VLESS_PRIVATE_KEY
sed -e "s|\${VLESS_UUID}|$VLESS_UUID|g" \
    -e "s|\${VLESS_PRIVATE_KEY}|$VLESS_PRIVATE_KEY|g" \
    -e "s|\${VLESS_SHORT_ID}|$VLESS_SHORT_ID|g" \
    /etc/sing-box/config.template.json > /etc/sing-box/config.json
exec sing-box run -c /etc/sing-box/config.json
