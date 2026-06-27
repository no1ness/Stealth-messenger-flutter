#!/bin/sh
set -e

# Get superuser token
RESP=$(curl -s -X POST http://127.0.0.1:8092/api/superusers/auth-with-password \
  -H 'Content-Type: application/json' \
  -d '{"identity":"test@stealth.local","password":"testpass123"}')
echo "Auth response: $RESP"

TOKEN=$(echo "$RESP" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("token","") or d.get("data",{}).get("token",""))' 2>/dev/null)
echo "TOKEN=$TOKEN"

if [ -z "$TOKEN" ]; then
  echo "ERROR: Could not get superuser token"
  exit 1
fi

# Import rtc_signaling collection
echo "Importing rtc_signaling..."
IMPORT_RESULT=$(curl -s -X PUT http://127.0.0.1:8092/api/collections/import \
  -H 'Content-Type: application/json' \
  -H "Authorization: $TOKEN" \
  -d @/home/ruslan/projects/STEALTH/server/pocketbase/rtc_signaling_import.json)
echo "Import result: $IMPORT_RESULT"

# Import user_profiles if exists
if [ -f /home/ruslan/projects/STEALTH/docs/pb_schemas/user_profiles.json ]; then
  echo "Importing user_profiles..."
  IMPORT_RESULT2=$(curl -s -X PUT http://127.0.0.1:8092/api/collections/import \
    -H 'Content-Type: application/json' \
    -H "Authorization: $TOKEN" \
    -d @/home/ruslan/projects/STEALTH/docs/pb_schemas/user_profiles.json)
  echo "Import result2: $IMPORT_RESULT2"
fi

# List collections
echo "=== Collections ==="
curl -s http://127.0.0.1:8092/api/collections \
  -H "Authorization: $TOKEN" | \
  python3 -c 'import sys,json
for c in json.load(sys.stdin).get("items", []):
    print(f"  {c[\"name\"]} ({c[\"type\"]})")'
echo "=== Done ==="
