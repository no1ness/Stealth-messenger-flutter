#!/usr/bin/env bash
# Import rtc_signaling collection into a running PocketBase (local or production).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"

PB_URL="${POCKETBASE_URL:-http://127.0.0.1:8090}"
ADMIN_EMAIL="${POCKETBASE_ADMIN_EMAIL:-admin@test.local}"
ADMIN_PASSWORD="${POCKETBASE_ADMIN_PASSWORD:-}"
IMPORT_JSON="${POCKETBASE_IMPORT_JSON:-$REPO_ROOT/server/pocketbase/rtc_signaling_import.json}"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "Set POCKETBASE_ADMIN_PASSWORD (and optionally POCKETBASE_URL, POCKETBASE_ADMIN_EMAIL)." >&2
  exit 1
fi

TOKEN=""
if TOKEN_JSON=$(curl -sf -X POST "$PB_URL/api/admins/auth-with-password" \
  -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" 2>/dev/null); then
  TOKEN=$(echo "$TOKEN_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
else
  TOKEN=$(curl -sf -X POST "$PB_URL/api/collections/_superusers/auth-with-password" \
    -H 'Content-Type: application/json' \
    -d "{\"identity\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
fi

BODY=$(python3 -c "
import json, pathlib
collections = json.loads(pathlib.Path('$IMPORT_JSON').read_text())
print(json.dumps({'collections': collections, 'deleteMissing': False}))
")

HTTP_CODE=$(curl -s -o /tmp/pb-import.out -w '%{http_code}' -X PUT "$PB_URL/api/collections/import" \
  -H "Authorization: $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$BODY")

if [[ "$HTTP_CODE" == "204" ]]; then
  echo "Imported rtc_signaling into $PB_URL from $(basename "$IMPORT_JSON")"
  exit 0
fi

echo "Import failed (HTTP $HTTP_CODE):" >&2
cat /tmp/pb-import.out >&2
exit 1
