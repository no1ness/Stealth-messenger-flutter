#!/usr/bin/env bash
# Print PocketBase one-time setup checklist (admin UI steps).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"

if [[ -f "$DOCKER_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$DOCKER_DIR/.env"
fi

SIGNAL_DOMAIN="${SIGNAL_DOMAIN:-signal.example.com}"
IMPORT_JSON="$REPO_ROOT/server/pocketbase/rtc_signaling_import.json"

cat <<EOF
PocketBase one-time setup
=========================

1. Open https://${SIGNAL_DOMAIN}/_/ and create the first admin account.

2. Import rtc_signaling collection:
   Settings -> Import collections
   File: ${IMPORT_JSON}

3. Confirm API rules on rtc_signaling (should match import):
   List/View: target = @request.auth.id || creator = @request.auth.id
   Create:    @request.auth.id != "" && @request.body.creator = @request.auth.id
   Update:    (empty / null)
   Delete:    creator = @request.auth.id

4. users collection: keep public registration enabled (default).

5. Restart PocketBase to load pb_hooks:
   cd ~/stealth-server && docker compose restart pocketbase

6. Verify cron in Admin -> Settings -> Logs: rtc_cleanup every 10 minutes.

Hooks installed from server/pb_hooks/:
  - rtc_cleanup.pb.js   (TTL for signaling records)
  - push_dispatcher.pb.js (optional UnifiedPush; safe if pushSubscription unset)

EOF
