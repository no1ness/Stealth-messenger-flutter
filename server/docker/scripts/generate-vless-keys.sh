#!/bin/bash
set -euo pipefail
SG() {
  if command -v sing-box &>/dev/null; then
    sing-box "$@"
  else
    docker run --rm ghcr.io/sagernet/sing-box:latest "$@"
  fi
}
echo "=== Private/Public Key Pair ==="
SG generate reality-keypair
echo ""
echo "=== Short ID (8 hex) ==="
SG generate rand --hex 8
