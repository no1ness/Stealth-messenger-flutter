#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"
if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${SIGNAL_DOMAIN:?Set in .env}" : "${TURN_DOMAIN:?}" : "${VPS_PUBLIC_IP:?}"
PB_URL="${POCKETBASE_URL:-https://${SIGNAL_DOMAIN}}"
ADMIN_EMAIL="${POCKETBASE_ADMIN_EMAIL:-admin@test.local}"
ADMIN_PASSWORD="${POCKETBASE_ADMIN_PASSWORD:-}"
[[ -n "$ADMIN_PASSWORD" ]] || { echo "Set POCKETBASE_ADMIN_PASSWORD" >&2; exit 1; }
cd "$REPO_ROOT/client"
flutter pub get
export POCKETBASE_TEST_URL="$PB_URL" POCKETBASE_TEST_ADMIN_EMAIL="$ADMIN_EMAIL" POCKETBASE_TEST_ADMIN_PASSWORD="$ADMIN_PASSWORD"
flutter test test/services/signaling/pocketbase_signaling_smoke_test.dart
