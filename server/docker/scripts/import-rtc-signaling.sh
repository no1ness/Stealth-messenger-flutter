#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"
PB_URL="${POCKETBASE_URL:-http://127.0.0.1:8090}"
ADMIN_EMAIL="${POCKETBASE_ADMIN_EMAIL:-admin@test.local}"
ADMIN_PASSWORD="${POCKETBASE_ADMIN_PASSWORD:-}"
IMPORT_JSON="${POCKETBASE_IMPORT_JSON:-$REPO_ROOT/server/pocketbase/rtc_signaling_import.json}"
[[ -n "$ADMIN_PASSWORD" ]] || { echo "Set POCKETBASE_ADMIN_PASSWORD" >&2; exit 1; }
TOKEN=$(curl -sf -X POST "$PB_URL/api/admins/auth-with-password" -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" || \
  curl -sf -X POST "$PB_URL/api/collections/_superusers/auth-with-password" -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
BODY=$(python3 -c "import json,pathlib; c=json.loads(pathlib.Path('$IMPORT_JSON').read_text()); print(json.dumps({'collections':c,'deleteMissing':False}))")
HTTP=$(curl -s -o /tmp/pb-import.out -w '%{http_code}' -X PUT "$PB_URL/api/collections/import" -H "Authorization: $TOKEN" -H 'Content-Type: application/json' -d "$BODY")
[[ "$HTTP" == "204" ]] && echo "Imported rtc_signaling" && exit 0
cat /tmp/pb-import.out >&2; exit 1
