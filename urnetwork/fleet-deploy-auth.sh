#!/usr/bin/env bash
# Arcum URnetwork fleet clean-install + authenticate + start
# Run on the Ansible controller from a checked-out arc-installers repository.
set -Eeuo pipefail
umask 077

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
URNETWORK_DIR="$ROOT_DIR/urnetwork"
CREDENTIAL_FILE="${URNETWORK_CREDENTIAL_FILE:-$URNETWORK_DIR/credentials/provider-auth.enc.b64}"
KEY_FILE="${URNETWORK_CREDENTIAL_KEY_FILE:-/root/.config/arc-installers/urnetwork-jwt.openssl-key}"
INSTALLER="$URNETWORK_DIR/clean-install-urnetwork.sh"
INVENTORY="${ANSIBLE_INVENTORY:-/root/Jetsons/inventory.ini}"
GROUP="${ANSIBLE_GROUP:-jetsons_nodes}"
LIMIT=""
SKIP_INSTALL=0
YES=0

usage() {
  cat <<'EOF'
Usage:
  fleet-deploy-auth.sh [--limit HOST[,HOST...]] [--skip-install] [--yes]

Options:
  --limit HOSTS   Limit rollout to one or more inventory hosts (recommended for first test).
  --skip-install  Do not clean-reinstall; copy the JWT to the existing client and start it.
  --yes           Skip the interactive fleet confirmation.
  -h, --help      Show this help.

Environment:
  ANSIBLE_INVENTORY=/root/Jetsons/inventory.ini
  ANSIBLE_GROUP=jetsons_nodes
  URNETWORK_CREDENTIAL_KEY_FILE=/root/.config/arc-installers/urnetwork-jwt.openssl-key
  URNETWORK_CREDENTIAL_FILE=<path to encrypted .b64 file>

The JWT is decrypted only into a mode-600 temporary file on this controller.
It is copied to /root/.urnetwork/jwt on each selected VPS with mode 0600.
EOF
}

while (($#)); do
  case "$1" in
    --limit) [[ $# -ge 2 ]] || { echo "--limit requires a host or pattern" >&2; exit 2; }; LIMIT="$2"; shift 2 ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for cmd in ansible ansible-playbook openssl base64 sha256sum; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd" >&2; exit 1; }
done
[[ -r "$INVENTORY" ]] || { echo "Inventory not readable: $INVENTORY" >&2; exit 1; }
[[ -r "$CREDENTIAL_FILE" ]] || { echo "Encrypted credential file not readable: $CREDENTIAL_FILE" >&2; exit 1; }
[[ -r "$KEY_FILE" ]] || { echo "Decryption key not readable: $KEY_FILE" >&2; exit 1; }
if (( SKIP_INSTALL == 0 )); then
  [[ -r "$INSTALLER" ]] || { echo "Clean installer missing: $INSTALLER" >&2; exit 1; }
fi

TMP_DIR="$(mktemp -d)"
JWT_FILE="$TMP_DIR/provider.jwt"
CIPHER_FILE="$TMP_DIR/provider.enc"
cleanup() {
  if [[ -f "$JWT_FILE" ]]; then shred -u "$JWT_FILE" 2>/dev/null || rm -f "$JWT_FILE"; fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

base64 -d "$CREDENTIAL_FILE" > "$CIPHER_FILE"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -salt \
  -pass "file:$KEY_FILE" -in "$CIPHER_FILE" -out "$JWT_FILE"
chmod 600 "$JWT_FILE"
[[ -s "$JWT_FILE" ]] || { echo "Decrypted JWT is empty; aborting." >&2; exit 1; }

ANSIBLE_LIMIT_ARGS=()
[[ -n "$LIMIT" ]] && ANSIBLE_LIMIT_ARGS=(-l "$LIMIT")
export ANSIBLE_HOST_KEY_CHECKING="${ANSIBLE_HOST_KEY_CHECKING:-False}"
export ANSIBLE_DISPLAY_ARGS_TO_STDOUT=False

echo "URnetwork deployment target: $GROUP${LIMIT:+ (limit: $LIMIT)}"
echo "Inventory: $INVENTORY"
echo "Clean reinstall: $([[ $SKIP_INSTALL -eq 0 ]] && echo yes || echo no)"
echo "Credential: encrypted file decrypted and validated (value not displayed)"
echo
echo "Preflight: checking SSH connectivity..."
ansible "$GROUP" -i "$INVENTORY" "${ANSIBLE_LIMIT_ARGS[@]}" -m ping -f 10

if (( YES == 0 )); then
  echo
  if [[ -n "$LIMIT" ]]; then
    read -r -p "Proceed with URnetwork deployment to $LIMIT? [y/N] " answer
  else
    read -r -p "Proceed with deployment to the entire $GROUP group? This may replace existing URnetwork identities. [y/N] " answer
  fi
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled; no VPS was changed."; exit 0; }
fi

if (( SKIP_INSTALL == 0 )); then
  echo "Step 1/3: clean-installing the pinned official URnetwork client..."
  ansible "$GROUP" -i "$INVENTORY" "${ANSIBLE_LIMIT_ARGS[@]}" -b -m script -a "$INSTALLER" -f 5
fi

echo "Step 2/3: copying the authenticated provider credential..."
ansible "$GROUP" -i "$INVENTORY" "${ANSIBLE_LIMIT_ARGS[@]}" -b -m copy \
  -a "src=$JWT_FILE dest=/root/.urnetwork/jwt owner=root group=root mode=0600" -f 5

echo "Step 3/3: starting provider and enabling boot start..."
ansible "$GROUP" -i "$INVENTORY" "${ANSIBLE_LIMIT_ARGS[@]}" -b -m shell \
  -a 'set -eu; T=/root/.local/share/urnetwork-provider/bin/urnet-tools; test -x "$T"; "$T" auto-start on; "$T" start; "$T" status' -f 5

echo
echo "Deployment commands completed. Run a separate read-only fleet audit to confirm every host."
