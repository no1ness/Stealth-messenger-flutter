#!/usr/bin/env bash
# Build release APK with server URLs from server/docker/.env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"

if [[ -f "$DOCKER_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$DOCKER_DIR/.env"
fi

: "${SIGNAL_DOMAIN:?Set SIGNAL_DOMAIN in .env}"
: "${TURN_DOMAIN:?Set TURN_DOMAIN in .env}"
: "${TURN_USERNAME:?}"
: "${TURN_PASSWORD:?}"

POCKETBASE_URL="https://${SIGNAL_DOMAIN}"
TURN_URL="turn:${TURN_DOMAIN}:3478"
TURNS_URL="turns:${TURN_DOMAIN}:5349?transport=tcp"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found in PATH." >&2
  exit 1
fi

echo "==> Building release APK"
echo "    POCKETBASE_URL=$POCKETBASE_URL"
echo "    TURN_URL=$TURN_URL"
echo "    TURNS_URL=$TURNS_URL"

cd "$REPO_ROOT/client"
flutter pub get
flutter build apk --release \
  --dart-define="POCKETBASE_URL=${POCKETBASE_URL}" \
  --dart-define="TURN_URL=${TURN_URL}" \
  --dart-define="TURN_USERNAME=${TURN_USERNAME}" \
  --dart-define="TURN_PASSWORD=${TURN_PASSWORD}" \
  --dart-define="TURNS_URL=${TURNS_URL}" \
  --dart-define="TURNS_USERNAME=${TURN_USERNAME}" \
  --dart-define="TURNS_PASSWORD=${TURN_PASSWORD}"

APK="$REPO_ROOT/client/build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "APK: $APK"
ls -lh "$APK"
