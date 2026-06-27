#!/bin/bash
# Check PB health
echo "=== PB Health ==="
curl -s http://127.0.0.1:8092/api/health
echo ""

# Admin auth
echo "=== Admin Auth ==="
RESP=$(curl -s -X POST http://127.0.0.1:8092/api/admins/auth-with-password \
  -H "Content-Type: application/json" \
  -d '{"identity":"test@stealth.local","password":"testpass123"}')
echo "$RESP"
TOKEN=$(echo "$RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
echo "Token: ${TOKEN:0:20}..."

if [ -z "$TOKEN" ]; then
  echo "Creating admin..."
  docker exec pb-test pocketbase admin create test@stealth.local testpass123
  RESP=$(curl -s -X POST http://127.0.0.1:8092/api/admins/auth-with-password \
    -H "Content-Type: application/json" \
    -d '{"identity":"test@stealth.local","password":"testpass123"}')
  TOKEN=$(echo "$RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  echo "New token: ${TOKEN:0:20}..."
fi

# Create or fix collections
echo "=== Ensure Collections ==="

for COLL in "rtc_signaling" "user_profiles"; do
  EXISTS=$(curl -s "http://127.0.0.1:8092/api/collections/$COLL" -H "Authorization: Bearer $TOKEN" | grep -c '"id":')
  if [ "$EXISTS" -gt 0 ]; then
    echo "$COLL exists, patching createRule..."
    curl -s -X PATCH "http://127.0.0.1:8092/api/collections/$COLL" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $TOKEN" \
      -d '{"createRule":"@request.auth.id != \"\""}'
    echo ""
  else
    echo "$COLL does not exist, creating..."
    if [ "$COLL" = "rtc_signaling" ]; then
      curl -s -X POST "http://127.0.0.1:8092/api/collections" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{
          "name":"rtc_signaling","type":"base",
          "schema":[
            {"name":"roomId","type":"text","required":true},
            {"name":"creator","type":"text","required":true},
            {"name":"target","type":"text","required":true},
            {"name":"type","type":"select","required":true,"options":{"maxSelect":1,"values":["offer","answer","candidate","hangup"]}},
            {"name":"payload","type":"json","options":{"maxSize":2000000}}
          ],
          "listRule":"target = @request.auth.id || creator = @request.auth.id",
          "viewRule":"target = @request.auth.id || creator = @request.auth.id",
          "createRule":"@request.auth.id != \"\"",
          "deleteRule":"creator = @request.auth.id"
        }'
    else
      curl -s -X POST "http://127.0.0.1:8092/api/collections" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{
          "name":"user_profiles","type":"base",
          "schema":[
            {"name":"userId","type":"text","required":true},
            {"name":"publicKey","type":"text"},
            {"name":"deviceModel","type":"text"},
            {"name":"platform","type":"text"},
            {"name":"appVersion","type":"text"},
            {"name":"registeredAt","type":"date"},
            {"name":"isOnline","type":"bool"},
            {"name":"lastSeen","type":"date"}
          ],
          "listRule":"@request.auth.id != \"\"",
          "viewRule":"@request.auth.id != \"\"",
          "createRule":"@request.auth.id != \"\"",
          "updateRule":"userId = @request.auth.id"
        }'
    fi
    echo ""
  fi
done
echo "=== Done ==="
