#!/usr/bin/env bash
set -eu

cat > /tmp/import.json <<'JSON'
[{"name":"rtc_signaling","type":"base","schema":[{"name":"roomId","type":"text","required":true,"id":"room"},{"name":"sender","type":"text","required":true,"id":"sender"},{"name":"target","type":"text","required":true,"id":"target"},{"name":"payload","type":"json"},{"name":"type","type":"text","required":true,"id":"type"}],"listRule":"(target = @request.auth.id) || (sender = @request.auth.id)","viewRule":"(target = @request.auth.id) || (sender = @request.auth.id)","createRule":"(target = @request.auth.id) || (sender = @request.auth.id)"}]
JSON

TOKEN=$(curl -sS -X POST "http://localhost:8090/api/admins/auth-with-password" -H "Content-Type: application/json" -d '{"identity":"admin@stealthpro.ru","password":"z180687@S"}' | python3 -c "import sys,json;t=json.load(sys.stdin);print(t.get('token',''))")

curl -sS -X PUT "http://localhost:8090/api/collections/import" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d @/tmp/import.json

echo IMPORT_OK
