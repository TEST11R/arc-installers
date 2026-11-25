#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

BASE="https://raw.githubusercontent.com/TEST11R/arc-installers/main/urnetwork"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TOKEN="$TMP/jwt"
CLEAN="$TMP/clean-install-urnetwork.sh"
EXPECTED="52179ad12f43a5d65be7e652aaedacac39986a0c48ff4d5a32f8302c4c19256f"

if [[ "$EUID" -ne 0 ]]; then
  echo "Run from a root login shell." >&2
  exit 1
fi

echo "[1/6] Fetching repository credential and clean installer..."
curl -fsSL "$BASE/jwt" -o "$TOKEN"
tr -d '\r\n' < "$TOKEN" > "$TMP/jwt.clean"
mv "$TMP/jwt.clean" "$TOKEN"
curl -fsSL "$BASE/clean-install-urnetwork.sh" -o "$CLEAN"

[[ -s "$TOKEN" ]] || { echo "Repository credential is empty." >&2; exit 1; }
[[ "$(wc -c < "$TOKEN")" -ge 100 ]] || { echo "Credential is too short." >&2; exit 1; }
[[ "$(sha256sum "$CLEAN" | awk '{print $1}')" == "$EXPECTED" ]] || {
  echo "Clean installer checksum mismatch; existing installation left untouched." >&2
  exit 1
}

echo "[2/6] Removing any existing URnetwork installation and identity..."
env -u SUDO_USER sh "$CLEAN"

echo "[3/6] Installing repository credential..."
install -d -o root -g root -m 0700 /root/.urnetwork
install -o root -g root -m 0600 "$TOKEN" /root/.urnetwork/jwt

echo "[4/6] Enabling root user services at boot..."
loginctl enable-linger root
systemctl start user-runtime-dir@0.service
systemctl start user@0.service
export XDG_RUNTIME_DIR=/run/user/0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus

TOOLS=/root/.local/share/urnetwork-provider/bin/urnet-tools
[[ -x "$TOOLS" ]] || { echo "urnet-tools was not installed." >&2; exit 1; }
"$TOOLS" auto-start on
"$TOOLS" start

DROPIN="/root/.config/systemd/user/urnetwork.service.d/10-arcum-restart.conf"
install -d -o root -g root -m 0700 "$(dirname "$DROPIN")"
cat > "$DROPIN" <<'EOF'
[Service]
Restart=on-failure
RestartSec=30s
EOF
chmod 0600 "$DROPIN"
systemctl --user daemon-reload
systemctl --user enable urnetwork.service
systemctl --user restart urnetwork.service
sleep 3

echo "[5/6] Checking service and provider status..."
SERVICE_STATE="$(systemctl --user is-active urnetwork.service)"
SERVICE_ENABLED="$(systemctl --user is-enabled urnetwork.service)"
STATUS_OUTPUT="$("$TOOLS" status 2>&1)"
printf '%s\\n' "$STATUS_OUTPUT"
echo "systemd service: $SERVICE_STATE"
echo "boot enablement: $SERVICE_ENABLED"
[[ "$SERVICE_STATE" == "active" ]] || { echo "Provider service is not active." >&2; exit 1; }
[[ "$SERVICE_ENABLED" == "enabled" ]] || { echo "Provider service is not enabled at boot." >&2; exit 1; }
grep -Eiq 'signed[[:space:]]*in[^[:alnum:]]*yes' <<<"$STATUS_OUTPUT" || {
  echo "Signed-in state was not confirmed." >&2; exit 1;
}
grep -Eiq 'registered[^[:alnum:]]*yes' <<<"$STATUS_OUTPUT" || {
  echo "Registered state was not confirmed." >&2; exit 1;
}
grep -Eiq 'running[^[:alnum:]]*(active|yes)' <<<"$STATUS_OUTPUT" || {
  echo "Running state was not confirmed." >&2; exit 1;
}

echo "[6/6] Credential permissions:"
stat -c '%a %U:%G %n' /root/.urnetwork/jwt
echo "Done. Provider auto-start is enabled."
