#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${SIGNAL_DOMAIN:?}"
: "${WEB_DOMAIN:=app.${SIGNAL_DOMAIN#signal.}}"

FAIL=0

echo "[verify-web] Checking https://${WEB_DOMAIN}/ ..."

HTTP_CODE=$(curl -sSf -o /dev/null -w "%{http_code}" "https://${WEB_DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "[verify-web] ✅ Root URL returned HTTP 200"
else
  echo "[verify-web] ❌ Root URL returned HTTP ${HTTP_CODE} (expected 200)"
  FAIL=1
fi

CONTENT_TYPE=$(curl -sSf -o /dev/null -w "%{content_type}" "https://${WEB_DOMAIN}/" 2>/dev/null || echo "")
if echo "$CONTENT_TYPE" | grep -qi "text/html"; then
  echo "[verify-web] ✅ Content-Type contains text/html"
else
  echo "[verify-web] ❌ Content-Type is '${CONTENT_TYPE}' (expected text/html)"
  FAIL=1
fi

BOOTSTRAP_CODE=$(curl -sSf -o /dev/null -w "%{http_code}" "https://${WEB_DOMAIN}/flutter_bootstrap.js" 2>/dev/null || echo "000")
if [[ "$BOOTSTRAP_CODE" == "200" ]]; then
  echo "[verify-web] ✅ flutter_bootstrap.js returned HTTP 200"
else
  echo "[verify-web] ❌ flutter_bootstrap.js returned HTTP ${BOOTSTRAP_CODE} (expected 200)"
  FAIL=1
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "[verify-web] ✅ All checks passed"
else
  echo "[verify-web] ❌ Some checks failed"
fi
exit "$FAIL"
