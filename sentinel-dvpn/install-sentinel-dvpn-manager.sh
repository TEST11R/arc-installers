#!/usr/bin/env bash
set -Eeuo pipefail

# Arcum: install Sentinel dVPN Node Manager (Debian 11/12, Ubuntu 20.04/22.04/24.04)
[[ ${EUID} -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }
command -v apt-get >/dev/null || { echo "This installer requires apt."; exit 1; }
. /etc/os-release
case "${ID:-}" in
  debian)
    case "${VERSION_ID:-}" in
      11) ppa_suite=focal ;;
      12) ppa_suite=jammy ;;
      *) echo "Unsupported Debian release: ${VERSION_ID:-unknown}"; exit 1 ;;
    esac
    ;;
  ubuntu)
    case "${VERSION_CODENAME:-}" in
      focal|jammy|noble) ppa_suite="${VERSION_CODENAME}" ;;
      *) echo "Unsupported Ubuntu release: ${VERSION_CODENAME:-unknown}"; exit 1 ;;
    esac
    ;;
  *) echo "Unsupported OS: ${ID:-unknown}"; exit 1 ;;
esac
[[ "$(dpkg --print-architecture)" == amd64 ]] || { echo "This installer currently supports amd64 only."; exit 1; }

export DEBIAN_FRONTEND=noninteractive

# Debian 11 reached end of LTS; its security repository is archived.
# Redirect stale security.debian.org entries to the official archive.
if [[ "${ID}" == debian && "${VERSION_ID}" == 11 ]]; then
  for source_file in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
    [[ -f "$source_file" ]] || continue
    sed -i 's#https\?://security.debian.org/debian-security#http://archive.debian.org/debian-security#g' "$source_file"
  done
fi

echo "[1/6] Updating package indexes..."
apt-get -o Acquire::Check-Valid-Until=false update
echo "[2/6] Installing prerequisites and Docker..."
apt-get install -y ca-certificates curl gnupg jq whiptail git openssl docker.io
systemctl enable --now docker

echo "[3/6] Verifying and installing the Foxinou PPA signing key..."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x1E4DCBDC436F95468F1FEB793B604A1F5EE3D8E5' -o "$tmp/foxinou.asc"
fingerprint="$(gpg --show-keys --with-colons "$tmp/foxinou.asc" | awk -F: '$1=="fpr"{print $10; exit}')"
[[ "$fingerprint" == "1E4DCBDC436F95468F1FEB793B604A1F5EE3D8E5" ]] || { echo "PPA signing-key fingerprint mismatch: $fingerprint"; exit 1; }
install -d -m 0755 /etc/apt/keyrings
gpg --dearmor --yes -o /etc/apt/keyrings/foxinou-dvpn-node-manager.gpg "$tmp/foxinou.asc"
chmod 0644 /etc/apt/keyrings/foxinou-dvpn-node-manager.gpg

echo "[4/6] Configuring the Sentinel Node Manager repository..."
printf 'deb [signed-by=/etc/apt/keyrings/foxinou-dvpn-node-manager.gpg] http://ppa.launchpad.net/foxinou/dvpn-node-manager/ubuntu %s main\n' "$ppa_suite" > /etc/apt/sources.list.d/foxinou-dvpn-node-manager.list
apt-get update

echo "[5/6] Installing the Node Manager..."
apt-get install -y dvpn-node-manager
usermod -aG docker root

echo "[6/6] Verifying installation..."
docker info >/dev/null
command -v dvpn-node-manager >/dev/null
dvpn-node-manager help
echo
echo "SUCCESS: Docker and Sentinel dVPN Node Manager are installed."
echo "Next: run 'sudo dvpn-node-manager' in an interactive terminal to configure the node."
echo "This installer does NOT create/import a wallet or start a node."
