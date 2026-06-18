[← PocketBase Setup](POCKETBASE_SETUP.md) · [Back to README](../README.md) · [Android Release →](ANDROID_RELEASE.md)

# Bypass censorship setup (Sing-box / VLESS-Reality)

## Architecture

```
[Client sing-box (Android)]
  inbound SOCKS5 :10808 + HTTP :10809
  outbound VLESS-Reality → Server :443
    disguised as telemost.yandex.ru (TLS SNI)
      → Server sing-box :443 (Reality)
        → Caddy :8443 (PocketBase API)
```

When bypass is **off**, traffic goes directly to Caddy's fallback port.

## Server setup

### Generate keys

```bash
cd server/docker
bash scripts/generate-vless-keys.sh
```

Output: keypair (private + public) + 8-char short ID.

### Configure `.env`

```env
VLESS_UUID=<uuid>
VLESS_PRIVATE_KEY=<private-key>
VLESS_SHORT_ID=<8-hex-chars>
```

Docker deploy (default):
```bash
bash scripts/install.sh
```

Native deploy:
```bash
bash scripts/deploy-native.sh
```

## Client setup

Build with:

```bash
flutter build apk --dart-define=BYPASS_SERVER_IP=<vps-ip> \
  --dart-define=BYPASS_UUID=<uuid> \
  --dart-define=BYPASS_PUBLIC_KEY=<public-key> \
  --dart-define=BYPASS_SHORT_ID=<short-id>
```

Or edit `client/.env.defaults` (local dev only, skip-worktree).

## Usage

Settings → Connection & Storage → Censorship bypass toggle.

When enabled:
- Sing-box starts on the device (SOCKS5 :10808 / HTTP :10809)
- PocketBase traffic routes through the HTTP CONNECT proxy
- SSE subscriptions reconnect automatically
- WebRTC ICE/STUN/TURN use system sockets (unaffected by proxy)

## Impact on web

Port 443 is owned by sing-box. Web app and dashboard move to fallback ports (default `:8445`, `:8446`). Configure via `WEB_FALLBACK_PORT` and `DASHBOARD_FALLBACK_PORT`.

## Manual probe

```bash
# Server — should show Yandex.Telemost TLS handshake
curl -k https://<vps-ip>:443

# Client — proxy active
curl -x http://127.0.0.1:10809 https://signal.stealthpro.ru/api/health
```

## See Also

- [PocketBase Setup](POCKETBASE_SETUP.md) — развёртывание signaling-сервера
- [Deployment](deployment.md) — деплой и CI/CD
- [Security](SECURITY.md) — модель угроз и криптография
