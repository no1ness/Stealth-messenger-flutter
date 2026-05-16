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

| Field      | Type         | Required | Notes                                                                                                                                  |
| ---------- | ------------ | -------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `roomId`   | text         | yes      | indexed; equals chatId for 1-to-1 calls                                                                                                |
| `creator`  | text         | yes      | PocketBase record id of the sender (15-char SHA-256 prefix of the local UUID — see `client/lib/services/signaling/pb_user_id.dart`)    |
| `target`   | text         | yes      | indexed; PocketBase record id of the receiver (same 15-char derivation as `creator`)                                                   |
| `type`     | select       | yes      | values: `offer`, `answer`, `candidate`, `hangup`                                                                                       |
| `payload`  | json         | yes      | raw SDP / candidate object passed verbatim. For `offer` and `hangup` it also carries `creatorUuid` (the sender's local UUID) so the receiver can resolve callers that aren't yet in its contact book — the 15-char hash is one-way |

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
PocketBase account whose `id` is **exactly 15 characters** — PocketBase
constrains custom record ids to that length and to the alphabet
`^[A-Za-z0-9_]{15}$`. The client derives the id deterministically as the
first 15 hex chars of `SHA-256(localUuid)` (see
`client/lib/services/signaling/pb_user_id.dart`); registration happens in
`PocketBaseAuthService.ensureAuth` (shared singleton used by both the
per-call `WebRtcSignalingService` and the global
`IncomingCallSignalingService`).

The mapping is one-way: given a PocketBase id you cannot reconstruct the
local UUID. For peer-resolution on the receiver side, the client builds a
`PbUserIdResolver` over its own UUID plus every contact UUID; for callers
not yet in the contact book the `offer`/`hangup` payload carries
`creatorUuid` explicitly.

If you prefer the `creator`/`target` fields to be `relation` instead of
`text`, change the type and update the rules to use `creator.id` /
`target.id`. The Stealth client treats the field as opaque ID either way.

> **Upgrading from an earlier Stealth build.** Releases before
> 2026-05-16 derived the PocketBase id by stripping dashes from the UUID
> (32 chars), which PocketBase silently rejected — the server generated a
> fresh id instead and the `auth.id == request.data.creator` rule never
> matched, so callees never received SSE events. On the first run after
> upgrading, the client detects the mismatch in secure storage, wipes its
> local credentials, and registers a fresh account under the correct
> 15-char id. The old server-side record is left as an orphan and is
> reaped by the cleanup hook (Section 5) once the user's TTL window passes.

## 4. Users collection

PocketBase ships a `users` auth collection by default; nothing extra is
required. The client uses `email + password` auth with synthetic credentials
of the form `<pbId>@stealth.local` (where `pbId` is the 15-char derivation
described above). Allow public sign-ups (the default) or call
`pb.collection('users').create()` from your own admin tooling — the client
logs in via password once the record exists.

## 5. Scheduled cleanup (TTL)

Without cleanup the collection grows by every signaling message. Add a hook
at `pb_hooks/rtc_cleanup.pb.js` to delete records older than 1 hour:

```js
// Runs every 10 minutes, keeps only the last hour of signaling traffic.
cronAdd("rtc_cleanup", "*/10 * * * *", () => {
  const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  $app.dao().db()
    .newQuery("DELETE FROM rtc_signaling WHERE created < {:cutoff}")
    .bind({ cutoff })
    .execute();
});
```

Reload the hooks (`docker compose restart pocketbase`) — you should see the
job in `_/#/settings/logs`.

If you need stronger guarantees (e.g. delete on disconnect), drive the
cleanup from the application layer instead: each peer issues
`pb.collection('rtc_signaling').delete(record.id)` after consuming the record.
Stealth's current implementation does NOT do this; the SQL TTL above is
sufficient for typical call traffic.

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
