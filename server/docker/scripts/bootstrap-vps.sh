#!/usr/bin/env bash
# Bootstrap a clean Ubuntu/Debian VPS for Stealth signaling stack.
# Run on the server as a user with sudo:
#   curl -fsSL ... | bash
# or:
#   ./scripts/bootstrap-vps.sh
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run as a normal user with sudo, not root." >&2
  exit 1
fi

echo "==> Updating packages"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  ca-certificates curl git ufw gettext-base

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker"
  curl -fsSL https://get.docker.com | sudo sh
fi

if ! groups "$USER" | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$USER"
  echo "Added $USER to group docker — run 'newgrp docker' or re-login before compose."
fi

echo "==> Configuring UFW"
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3478/tcp
sudo ufw allow 3478/udp
sudo ufw allow 5349/tcp
sudo ufw allow 49152:65535/udp
sudo ufw --force enable
sudo ufw status

echo "==> Docker version"
docker compose version

echo ""
echo "Bootstrap complete. Next:"
echo "  1. Point DNS A records to this host (see docs/DEPLOYMENT.md)"
echo "  2. Clone repo or copy server/docker to the VPS"
echo "  3. cp .env.example .env && edit .env"
echo "  4. ./scripts/install.sh"
