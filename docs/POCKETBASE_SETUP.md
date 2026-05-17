# PocketBase Signaling Server — Setup Guide

This document describes how to deploy the PocketBase backend that the Stealth
Messenger uses as a WebRTC signaling channel (offer / answer / candidate /
hangup). Once `POCKETBASE_URL` in `client/.env` points at a reachable instance
the calls work end-to-end with no legacy cloud backend involvement.

The Stealth client only needs:

- A reachable PocketBase URL (HTTPS recommended, plain HTTP only for local
  development).
- A `users` collection with email+password authentication (PocketBase ships
  with one out of the box).
- A custom `rtc_signaling` collection — see schema below.
- A scheduled cleanup hook so the collection does not grow indefinitely.

The signaling layer ignores the rest of the PocketBase featureset; you can
self-host the binary on a VPS, a homelab MikroTik container, or any container
runtime.

## 1. Deploy the binary

### 1.1 Local / VPS via docker compose

Drop the snippet below in `pocketbase/docker-compose.yml` next to a
`pb_data/` volume:

```yaml
services:
  pocketbase:
    image: ghcr.io/muchobien/pocketbase:latest
    restart: unless-stopped
    environment:
      - TZ=UTC
    volumes:
      - ./pb_data:/pb_data
    ports:
      - "127.0.0.1:8090:8090"

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    depends_on: [pocketbase]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    ports:
      - "80:80"
      - "443:443"

volumes:
  caddy_data:
  caddy_config:
```

Minimal `Caddyfile` (replace `signal.example.com` with your domain):

```
signal.example.com {
    reverse_proxy pocketbase:8090
}
```

After `docker compose up -d` the admin UI is available at
`https://signal.example.com/_/`. Create the first admin via the prompt that
appears in the container logs (`docker compose logs pocketbase`).

### 1.2 MikroTik containers (RouterOS 7.4+)

PocketBase is a single Go binary, so it fits the RouterOS container runtime
nicely. Pull the same image, mount `/disk1/pb_data` for persistence, and add a
NAT rule so port 443 reaches the Caddy container. A full walkthrough is out of
scope for this document, but the key tested settings are:

- `interface veth` with bridge to the LAN bridge.
- `container envs` with `TZ=UTC`.
- `container mounts` with `dst=/pb_data, src=/disk1/pb_data`.
- Start order: PocketBase → Caddy.

If you front the container with the MikroTik DNS, point `signal.<your-domain>`
at the router and let Caddy obtain the Let's Encrypt certificate via HTTP-01.

### 1.3 TLS notes

The Stealth client refuses to start when `POCKETBASE_URL` is empty (see
`client/lib/main.dart`), but it does NOT pin certificates. For production
make sure the URL is HTTPS and the cert is trusted by the device. Caddy with
the default ACME flow is sufficient.

## 2. Schema for `rtc_signaling`

Create the collection from the admin UI (Collections → New collection →
`base`), or import the JSON below via Settings → Import collections.

| Field      | Type         | Required | Notes                                                       |
| ---------- | ------------ | -------- | ----------------------------------------------------------- |
| `roomId`   | text         | yes      | indexed; equals chatId for 1-to-1 calls                     |
| `creator`  | text         | yes      | local user UUID of the sender (not relation: see Section 4) |
| `target`   | text         | yes      | indexed; local user UUID of the receiver                    |
| `type`     | select       | yes      | values: `offer`, `answer`, `candidate`, `hangup`            |
| `payload`  | json         | yes      | raw SDP / candidate object passed verbatim                  |

Recommended indexes (Settings → Indexes):

```
CREATE INDEX idx_rtc_signaling_target_created
  ON rtc_signaling (target, created);
CREATE INDEX idx_rtc_signaling_room
  ON rtc_signaling (roomId);
```

The `created` index makes the cleanup query (Section 5) cheap; the `roomId`
index is for ad-hoc debugging in the admin UI.

## 3. API rules

Set the rules on the `rtc_signaling` collection so each user only sees
messages addressed to them and can only post messages signed with their own
identity:

- **List / View rule**

  ```
  target = @request.auth.id || creator = @request.auth.id
  ```

- **Create rule**

  ```
  @request.auth.id != "" && @request.data.creator = @request.auth.id
  ```

- **Update rule**

  ```
  null
  ```

- **Delete rule**

  ```
  creator = @request.auth.id
  ```

These rules assume the `creator` field holds the PocketBase user id (the
authenticated `users.id`). Stealth's lazy auth flow registers a per-device
PocketBase account whose id matches the local user UUID written into
`creator`/`target` (see `client/lib/services/signaling/webrtc_signaling_service.dart`,
method `_ensureAuth`).

If you prefer the `creator`/`target` fields to be `relation` instead of
`text`, change the type and update the rules to use `creator.id` /
`target.id`. The Stealth client treats the field as opaque ID either way.

## 4. Users collection

PocketBase ships a `users` auth collection by default; nothing extra is
required. The client uses `email + password` auth with synthetic credentials
of the form `<localUuid>@stealth.local`. Allow public sign-ups (the default)
or call `pb.collection('users').create()` from your own admin tooling — the
client logs in via password once the record exists.

## 5. Scheduled cleanup (TTL)

`rtc_signaling` is a transient transport — once a peer has consumed an
offer/answer/candidate, the row has no purpose. Leaving rows around forever
lets a PocketBase admin reconstruct a long-tail call graph
(who-called-whom-when-from-which-device) from `creator`/`target` even
without decrypting SDP. The TTL hook bounds that window.

The hook is **version-controlled in this repository** at
[`pb_hooks/rtc_cleanup.pb.js`](../pb_hooks/rtc_cleanup.pb.js). Deploy it by
copying the file to your PocketBase install:

```bash
# from the Stealth repo root
cp pb_hooks/rtc_cleanup.pb.js /path/to/pocketbase/pb_hooks/
# or, for docker-compose installs:
docker compose cp pb_hooks/rtc_cleanup.pb.js pocketbase:/pb/pb_hooks/
```

Restart PocketBase so the hook is registered:

```bash
systemctl restart pocketbase      # systemd install
docker compose restart pocketbase # docker compose install
```

The hook runs hourly (`0 * * * *`) and deletes every `rtc_signaling` row
where `created < now - 24h`. To verify it is loaded, open the admin UI →
Logs and filter for `[rtcSignalingCleanup]`. You should see a sweep entry
at the top of each hour:

```
[rtcSignalingCleanup] swept N stale rows, deleted N, cutoff=...
```

To change the retention window, edit the `RETENTION_MS` constant in the
hook and redeploy. Keep it strictly greater than the longest expected
handshake (a few minutes worst-case under TURN / cold mobile).

If you need stronger guarantees (e.g. delete on disconnect), drive the
cleanup from the application layer instead: each peer issues
`pb.collection('rtc_signaling').delete(record.id)` after consuming the
record. Stealth's current implementation does NOT do this; the TTL above
is sufficient for typical call traffic.

## 6. Verifying the deployment

From the Stealth client root:

```bash
export POCKETBASE_TEST_URL=https://signal.example.com
flutter test test/services/signaling/pocketbase_signaling_smoke_test.dart
```

The test exchanges offer → answer → hangup between two synthetic users using
the real backend. If you also export `POCKETBASE_TEST_ADMIN_EMAIL` and
`POCKETBASE_TEST_ADMIN_PASSWORD` it will clean up the throwaway users at the
end.

A green run confirms:

1. The server is reachable from the host running `flutter test`.
2. The `rtc_signaling` schema and rules are correct.
3. Realtime SSE delivers in-room messages within ~10 seconds.

## 7. Operational notes

- **Backups.** PocketBase stores everything in `pb_data/data.db` (SQLite).
  Snapshot the volume from the admin UI (Settings → Backup) or with
  filesystem-level tooling.
- **Monitoring.** Hook PocketBase access logs into your logging stack — the
  client tags signaling errors with `[signaling]`, so cross-referencing is
  straightforward.
- **TURNS.** PocketBase only carries signaling. Media still needs a TURN /
  TURNS server; the client expects `TURNS_URL`, `TURNS_USERNAME`,
  `TURNS_PASSWORD` to be configured separately (typically `coturn` behind
  Caddy on port 443).
- **Scale.** A single PocketBase instance handles thousands of concurrent
  SSE clients on commodity hardware. Horizontal scaling is not currently
  supported by PocketBase; if you outgrow one node, move signaling to a
  managed pub/sub instead.
