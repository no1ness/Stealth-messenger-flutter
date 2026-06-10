#!/usr/bin/env bash
# Run PocketBase signaling smoke test from the dev machine (repo root required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"

if [[ -f "$DOCKER_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$DOCKER_DIR/.env"
fi

POCKETBASE_TEST_URL="${POCKETBASE_TEST_URL:-https://${SIGNAL_DOMAIN:-}}"
if [[ -z "$POCKETBASE_TEST_URL" || "$POCKETBASE_TEST_URL" == "https://" ]]; then
  echo "Set POCKETBASE_TEST_URL or SIGNAL_DOMAIN in .env" >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found in PATH." >&2
  exit 1
fi

export POCKETBASE_TEST_URL
export POCKETBASE_TEST_ADMIN_EMAIL="${POCKETBASE_TEST_ADMIN_EMAIL:-${POCKETBASE_ADMIN_EMAIL:-admin@test.local}}"
export POCKETBASE_TEST_ADMIN_PASSWORD="${POCKETBASE_TEST_ADMIN_PASSWORD:-${POCKETBASE_ADMIN_PASSWORD:-}}"
if [[ -z "$POCKETBASE_TEST_ADMIN_PASSWORD" ]]; then
  echo "Set POCKETBASE_TEST_ADMIN_PASSWORD or POCKETBASE_ADMIN_PASSWORD in .env" >&2
  exit 1
fi

echo "==> Smoke test against $POCKETBASE_TEST_URL"
cd "$REPO_ROOT/client"
flutter pub get
flutter test test/services/signaling/pocketbase_signaling_smoke_test.dart

echo ""
echo "Signaling smoke test passed."
