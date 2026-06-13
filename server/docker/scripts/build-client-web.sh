#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"
if [[ -f "$DOCKER_DIR/.env" ]]; then source "$DOCKER_DIR/.env"; fi
: "${SIGNAL_DOMAIN:?}" : "${TURN_DOMAIN:?}" : "${TURN_USERNAME:?}" : "${TURN_PASSWORD:?}"
cd "$REPO_ROOT/client"
echo "[build-client-web] flutter pub get..."
flutter pub get
echo "[build-client-web] flutter build web --release..."
START_SECONDS=$SECONDS
flutter build web --release --no-tree-shake-icons \
  --dart-define="POCKETBASE_URL=https://${SIGNAL_DOMAIN}" \
  --dart-define="TURN_URL=turn:${TURN_DOMAIN}:3478" \
  --dart-define="TURN_USERNAME=${TURN_USERNAME}" \
  --dart-define="TURN_PASSWORD=${TURN_PASSWORD}" \
  --dart-define="TURNS_URL=turns:${TURN_DOMAIN}:5349?transport=tcp" \
  --dart-define="TURNS_USERNAME=${TURN_USERNAME}" \
  --dart-define="TURNS_PASSWORD=${TURN_PASSWORD}"
ELAPSED=$((SECONDS - START_SECONDS))
echo "[build-client-web] build complete in ${ELAPSED}s"
ls -lh "$REPO_ROOT/client/build/web/"
