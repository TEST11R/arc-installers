#!/usr/bin/env bash
set -Eeuo pipefail

PPA_FINGERPRINT="1E4DCBDC436F95468F1FEB793B604A1F5EE3D8E5"
KEY_URL="https://raw.githubusercontent.com/TEST11R/arc-installers/main/sentinel-dvpn/ppa/foxinou-dvpn-node-manager.asc"
KEYRING="/etc/apt/keyrings/foxinou-dvpn-node-manager.gpg"
SOURCE="/etc/apt/sources.list.d/foxinou-dvpn-node-manager.list"

log() { printf '\n[Arcum Sentinel] %s\n' "$*"; }
die() { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "\n[ERROR] Installer stopped at line %s (exit %s). No automatic repository or security-source changes were made.\n" "$LINENO" "$rc" >&2; exit "$rc"' ERR

[ "$(id -u)" -eq 0 ] || die "Run as root: curl ... | sudo bash"
[ -r /etc/os-release ] || die "Cannot identify this Linux distribution."
. /etc/os-release

arch="$(dpkg --print-architecture 2>/dev/null || true)"
case "$arch" in amd64|arm64) ;; *) die "Unsupported CPU architecture: $arch. Supported: amd64 and arm64." ;; esac

suite=""
case "${ID:-}:${VERSION_ID:-}" in
  debian:11) suite="focal" ;;
  debian:12) suite="jammy" ;;
  ubuntu:24.04) suite="noble" ;;
  *) die "Unsupported OS: ${PRETTY_NAME:-unknown}. Supported by this installer: Debian 11, Debian 12, and Ubuntu 24.04." ;;
esac

export DEBIAN_FRONTEND=noninteractive
log "Detected ${PRETTY_NAME} ($arch); PPA suite: $suite"
log "Refreshing package indexes."
apt-get update

log "Installing prerequisite packages."
apt-get install -y ca-certificates curl gnupg

log "Downloading and verifying the Foxinou PPA signing key."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fL --retry 3 --connect-timeout 15 "$KEY_URL" -o "$tmp/ppa.asc"
actual="$(gpg --show-keys --with-colons "$tmp/ppa.asc" 2>/dev/null | awk -F: '$1=="fpr"{print toupper($10); exit}')"
[ "$actual" = "$PPA_FINGERPRINT" ] || die "PPA signing-key fingerprint mismatch. Expected $PPA_FINGERPRINT; got ${actual:-none}."
install -d -m 0755 /etc/apt/keyrings
gpg --dearmor --yes -o "$tmp/ppa.gpg" "$tmp/ppa.asc"
install -m 0644 "$tmp/ppa.gpg" "$KEYRING"
printf 'deb [signed-by=%s] http://ppa.launchpad.net/foxinou/dvpn-node-manager/ubuntu %s main\n' "$KEYRING" "$suite" > "$SOURCE"
chmod 0644 "$SOURCE"

log "Refreshing package indexes with the verified PPA."
apt-get update

log "Installing Docker and Sentinel dVPN Node Manager."
apt-get install -y docker.io dvpn-node-manager

log "Enabling Docker."
systemctl enable --now docker

# The manager checks the invoking sudo user for Docker group membership.
# Docker group membership is effectively root-equivalent; make this explicit.
install -d -m 0755 /etc
usermod -aG docker root
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && id "$SUDO_USER" >/dev/null 2>&1; then
  usermod -aG docker "$SUDO_USER"
  log "Added $SUDO_USER to the docker group (Docker access is root-equivalent)."
fi

command -v dvpn-node-manager >/dev/null 2>&1 || die "Package installed but dvpn-node-manager is not on PATH."
docker info >/dev/null 2>&1 || die "Docker is installed but its daemon is not responding."

log "Installation verified."
dvpn-node-manager help

if [ -t 1 ] && [ -r /dev/tty ]; then
  log "Opening the interactive Node Manager. Confirm inside its menu before creating/configuring a node."
  exec dvpn-node-manager </dev/tty
else
  log "Non-interactive install complete. Open an SSH terminal and run: sudo dvpn-node-manager"
fi
