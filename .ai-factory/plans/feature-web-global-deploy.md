# Implementation Plan: Web Global Deploy

Branch: feature/web-global-deploy
Created: 2026-06-13

## Settings
- Testing: yes
- Logging: verbose
- Docs: yes  (mandatory documentation checkpoint)

## Roadmap Linkage
Milestone: "M11 — Web rollout readiness"
Rationale: This plan delivers the core M11 milestone — makes the Flutter web build globally accessible via a public subdomain `app.stealthpro.ru` with production Caddy config, build/deploy scripts, and smoke test.

## Research Context
Source: Codebase exploration, `docs/deployment.md`, `server/docker/scripts/`, `.github/workflows/ci.yml`

Goal: Serve Flutter web release on `https://app.stealthpro.ru` with automatic HTTPS (Caddy), built with correct signaling dart-defines, deployed via SCP/rsync from the development machine or CI.

Constraints:
- VPS: 185.72.147.197, Ubuntu 26.04, 0.5 GB RAM / 7 GB NVMe (no Docker currently — native deployment)
- Caddy already serves `signal.stealthpro.ru` → reverse_proxy PocketBase on `:8090`
- Existing deploy scripts in `server/docker/scripts/` follow the pattern: source `.env` + build + push
- CI has `flutter build web --release --no-tree-shake-icons` as a validation step (no artifacts uploaded)

Decisions:
- Domain: `app.stealthpro.ru` (subdomain, clean separation from signaling)
- Caddy config: new site block alongside existing `signal.stealthpro.ru` block → `file_server` for static files
- Deploy flow: `build-client-web.sh` (local) → rsync `build/web/` to VPS → update Caddy → reload
- No Docker for web — static files served directly by Caddy on the host

Open questions: None — scope is clear.

## Tasks

### Phase 1: Build Script & Caddy Config

- [x] Task 1: Create `server/docker/scripts/build-client-web.sh`
  - Analogous to `build-client-apk.sh` but for `flutter build web --release`
  - Read `.env` from `server/docker/` for dart-defines (POCKETBASE_URL, TURN_*)
  - Add `--no-tree-shake-icons` (matching CI)
  - Output: `client/build/web/`
  - Logging: echo each step, log build time
  - Files: `server/docker/scripts/build-client-web.sh`

- [x] Task 2: Add Caddy `app.stealthpro.ru` site block to `deploy-native.sh`
  - Add web directory creation: `mkdir -p /var/www/stealth-web`
  - Add second site block in Caddyfile:
    ```
    app.stealthpro.ru {
        root * /var/www/stealth-web
        file_server
        encode gzip
    }
    ```
  - Ensure `systemctl reload caddy` is called
  - Files: `server/docker/scripts/deploy-native.sh`

- [x] Task 3: Create `server/docker/scripts/deploy-web.sh`
  - Sources `server/docker/.env`
  - Calls `build-client-web.sh`
  - Rsyncs `client/build/web/` to VPS: `rsync -avz --delete build/web/ root@185.72.147.197:/var/www/stealth-web/`
  - Ensures Caddy config is up to date on VPS (copies Caddy site block or runs a separate `caddy-update` step)
  - Reloads Caddy: `ssh root@185.72.147.197 "systemctl reload caddy"`
  - Verifies: `curl -sSf https://app.stealthpro.ru/ > /dev/null`
  - Logging: echo each step, log rsync time, log HTTP status
  - Files: `server/docker/scripts/deploy-web.sh`

### Phase 2: CI/CD & DNS

- [x] Task 4: Update `.env.example` with `WEB_DOMAIN` variable
  - Add `WEB_DOMAIN=app.example.com` (placeholder, used by build/deploy scripts)
  - Update `build-client-web.sh` and `deploy-web.sh` to use `WEB_DOMAIN`
  - Files: `server/docker/.env.example`, `server/docker/scripts/build-client-web.sh`, `server/docker/scripts/deploy-web.sh`

- [x] Task 5: Add web deploy smoke test
  - Create `server/docker/scripts/verify-web.sh`:
    - `curl -sSf -o /dev/null -w "%{http_code}" https://${WEB_DOMAIN}/`
    - Expect 200
    - Check `Content-Type` contains `text/html`
    - Check `flutter_bootstrap.js` returns 200
  - Files: `server/docker/scripts/verify-web.sh`

- [x] Task 6: Update documentation
  - Add new section to `docs/deployment.md`:
    - Prerequisites: DNS A record `app.stealthpro.ru → 185.72.147.197`
    - Build web: `./server/docker/scripts/build-client-web.sh`
    - Deploy: `./server/docker/scripts/deploy-web.sh`
    - Verify: `./server/docker/scripts/verify-web.sh`
    - Caddy automatically provisions Let's Encrypt TLS on first request
  - Update `README.md` web section if needed
  - Files: `docs/deployment.md`

<!-- Commit checkpoint: tasks 1-6 (single commit — all part of one feature) -->

## Commit Plan
- **Commit 1** (after tasks 1-6): `feat(web): add build/deploy scripts, Caddy config, and smoke test for app.stealthpro.ru`

## Verification
1. Run `./server/docker/scripts/build-client-web.sh` — produces `client/build/web/`
2. Run `./server/docker/scripts/verify-web.sh` against VPS — returns 200
3. Open `https://app.stealthpro.ru` in browser — app loads without errors
4. `docs/deployment.md` documents the full web deploy flow
