#!/usr/bin/env bash
# Verify DNS A records for SIGNAL_DOMAIN and TURN_DOMAIN resolve to VPS_PUBLIC_IP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$DOCKER_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$DOCKER_DIR/.env"
fi

: "${SIGNAL_DOMAIN:?Set SIGNAL_DOMAIN in .env}"
: "${TURN_DOMAIN:?Set TURN_DOMAIN in .env}"
: "${VPS_PUBLIC_IP:?Set VPS_PUBLIC_IP in .env}"

resolve_a() {
  local host="$1"
  if command -v dig >/dev/null 2>&1; then
    dig +short A "$host" | head -1
  elif command -v getent >/dev/null 2>&1; then
    getent ahosts "$host" | awk '/STREAM/ {print $1; exit}'
  else
    echo "Install dig or getent to check DNS." >&2
    exit 1
  fi
}

check_one() {
  local name="$1"
  local expected="$2"
  local got
  got="$(resolve_a "$name" || true)"
  if [[ -z "$got" ]]; then
    echo "FAIL  $name — no A record"
    return 1
  fi
  if [[ "$got" != "$expected" ]]; then
    echo "FAIL  $name -> $got (expected $expected)"
    return 1
  fi
  echo "OK    $name -> $got"
}

failed=0
check_one "$SIGNAL_DOMAIN" "$VPS_PUBLIC_IP" || failed=1
check_one "$TURN_DOMAIN" "$VPS_PUBLIC_IP" || failed=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "Fix DNS at your registrar, then re-run this script."
  exit 1
fi

echo ""
echo "DNS looks good for both hostnames."
