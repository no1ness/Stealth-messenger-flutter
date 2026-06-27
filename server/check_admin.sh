#!/bin/bash
RESP=$(curl -s -X POST http://127.0.0.1:8092/api/admins/auth-with-password \
  -H "Content-Type: application/json" \
  -d '{"identity":"test@stealth.local","password":"testpass123"}')
echo "$RESP"
