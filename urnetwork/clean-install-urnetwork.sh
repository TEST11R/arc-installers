#!/bin/sh
# Arcum URnetwork clean reinstall
# Removes the installed provider client, preserves ~/.urnetwork identity,
# then installs the latest official Linux provider using URnetwork's installer.
set -eu

INSTALL_URL="https://raw.githubusercontent.com/urnetwork/connect/main/scripts/Provider_Install_Linux.sh"
UNINSTALL_URL="https://raw.githubusercontent.com/urnetwork/connect/main/scripts/Provider_Uninstall_Linux.sh"
INSTALL_PATH="${URNETWORK_INSTALL_PATH:-$HOME/.local/share/urnetwork-provider}"
STATE_DIR="$HOME/.urnetwork"
TMP_INSTALL="$(mktemp)"
trap 'rm -f "$TMP_INSTALL"' EXIT HUP INT TERM

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    echo "Run this as the target provider user, not through sudo."
    echo "If you intend the provider to run as root, log in as root directly."
    exit 1
fi

command -v curl >/dev/null 2>&1 || {
    echo "curl is required." >&2
    exit 1
}

echo "URnetwork clean reinstall for: $(id -un)"
echo "Install path: $INSTALL_PATH"
echo "Identity directory: $STATE_DIR"
echo

# The official uninstaller deliberately preserves ~/.urnetwork unless
# --remove-identity is supplied. Never pass that destructive option here.
TOOLS=""
if command -v urnet-tools >/dev/null 2>&1; then
    TOOLS="$(command -v urnet-tools)"
elif [ -x "$INSTALL_PATH/bin/urnet-tools" ]; then
    TOOLS="$INSTALL_PATH/bin/urnet-tools"
fi

if [ -n "$TOOLS" ]; then
    echo "[1/4] Removing the existing provider client and service..."
    "$TOOLS" uninstall --no-modify-bashrc
elif [ -d "$INSTALL_PATH" ]; then
    echo "[1/4] Existing install found; using the official uninstaller..."
    curl -fsSL "$UNINSTALL_URL" | sh -s -- --no-modify-bashrc
else
    echo "[1/4] No existing provider installation found."
fi

echo
echo "[2/4] Downloading the official upstream installer..."
curl -fsSL "$INSTALL_URL" -o "$TMP_INSTALL"
grep -q 'api.github.com/repos/urnetwork/build' "$TMP_INSTALL" || {
    echo "Downloaded installer did not contain the expected official build-release API." >&2
    exit 1
}

echo
echo "[3/4] Installing the latest official Linux provider (install only; does not start it)..."
sh "$TMP_INSTALL" --no-start --no-modify-bashrc

echo
echo "[4/4] Verifying installation..."
if [ ! -x "$INSTALL_PATH/bin/urnet-tools" ] || [ ! -x "$INSTALL_PATH/bin/urnetwork" ]; then
    echo "Installation verification failed: expected provider binaries are missing." >&2
    exit 1
fi

"$INSTALL_PATH/bin/urnet-tools" version

if [ -f "$STATE_DIR/jwt" ]; then
    echo "Existing authentication file preserved: $STATE_DIR/jwt"
else
    echo "No JWT found at $STATE_DIR/jwt. Authenticate with: urnetwork auth"
fi

echo
echo "SUCCESS: fresh provider client installed."
echo "The provider has NOT been started. After authentication/JWT deployment, run:"
echo "  $INSTALL_PATH/bin/urnet-tools auto-start on"
echo "  $INSTALL_PATH/bin/urnet-tools start"
