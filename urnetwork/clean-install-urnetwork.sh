#!/bin/sh
# Arcum URnetwork FULL CLEAN REINSTALL
# Deletes this account's URnetwork client, JWT and identity, then installs
# the latest official Linux provider without authenticating or starting it.
set -eu

INSTALL_URL="https://raw.githubusercontent.com/urnetwork/connect/main/scripts/Provider_Install_Linux.sh"
UNINSTALL_URL="https://raw.githubusercontent.com/urnetwork/connect/main/scripts/Provider_Uninstall_Linux.sh"
INSTALL_PATH="${URNETWORK_INSTALL_PATH:-$HOME/.local/share/urnetwork-provider}"
STATE_DIR="$HOME/.urnetwork"
TIMER_STAMP="$HOME/.local/share/systemd/timers/stamp-urnetwork-update.timer"
TMP_INSTALL="$(mktemp)"
TMP_UNINSTALL="$(mktemp)"
trap 'rm -f "$TMP_INSTALL" "$TMP_UNINSTALL"' EXIT HUP INT TERM

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    echo "Run as the account that owns the URnetwork provider, not through sudo." >&2
    exit 1
fi
command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }

if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -S "/run/user/$(id -u)/bus" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
fi

echo "URnetwork FULL clean reinstall"
echo "Host: $(hostname)"
echo "Provider user: $(id -un)"
echo "Install path: $INSTALL_PATH"
echo "IDENTITY TO DELETE: $STATE_DIR"
echo

echo "[1/5] Fetching official upstream scripts..."
curl -fsSL "$UNINSTALL_URL" -o "$TMP_UNINSTALL"
curl -fsSL "$INSTALL_URL" -o "$TMP_INSTALL"
grep -q 'SCRIPT_VERSION=' "$TMP_UNINSTALL" || { echo "Uninstaller validation failed." >&2; exit 1; }
grep -q 'api.github.com/repos/urnetwork/build' "$TMP_INSTALL" || { echo "Installer validation failed." >&2; exit 1; }

echo
echo "[2/5] Stopping and removing legacy services, client and identity..."
# Remove a legacy system-level unit only when it explicitly identifies the
# URnetwork provider and executes this exact install path.
if [ -f /etc/systemd/system/urnetwork.service ]; then
    if grep -q '^Description=URnetwork Provider$' /etc/systemd/system/urnetwork.service &&
       grep -Fq "ExecStart=$INSTALL_PATH/bin/urnetwork provide" /etc/systemd/system/urnetwork.service; then
        systemctl disable --now urnetwork.service
        rm -f /etc/systemd/system/urnetwork.service
        systemctl daemon-reload
        systemctl reset-failed urnetwork.service 2>/dev/null || true
    elif grep -q '^# Installed by urnet-tools --system' /etc/systemd/system/urnetwork.service; then
        TOOLS=""
        if command -v urnet-tools >/dev/null 2>&1; then TOOLS="$(command -v urnet-tools)"
        elif [ -x "$INSTALL_PATH/bin/urnet-tools" ]; then TOOLS="$INSTALL_PATH/bin/urnet-tools"
        fi
        if [ -z "$TOOLS" ]; then
            echo "URnetwork system service found but its manager is missing; refusing partial removal." >&2
            exit 1
        fi
        "$TOOLS" uninstall --remove-identity --yes --no-modify-bashrc
    else
        echo "An unrelated or unrecognized /etc/systemd/system/urnetwork.service exists; refusing to touch it." >&2
        exit 1
    fi
fi

if [ -d "$INSTALL_PATH" ]; then
    sh "$TMP_UNINSTALL" --dest "$INSTALL_PATH" --remove-identity --no-modify-bashrc
elif [ -d "$STATE_DIR" ]; then
    echo "No provider install directory; deleting the remaining URnetwork identity directory."
    rm -rf "$STATE_DIR"
fi

rm -f "$TIMER_STAMP"

echo
echo "[3/5] Verifying old identity and running provider are gone..."
if [ -e "$INSTALL_PATH" ] || [ -e "$STATE_DIR" ]; then
    echo "Old install or identity remains; aborting." >&2
    ls -ld "$INSTALL_PATH" "$STATE_DIR" 2>/dev/null || true
    exit 1
fi
if systemctl --user is-active --quiet urnetwork.service 2>/dev/null ||
   systemctl is-active --quiet urnetwork.service 2>/dev/null; then
    echo "An URnetwork service is still active; aborting." >&2
    exit 1
fi
if pgrep -x urnetwork >/dev/null 2>&1; then
    echo "An urnetwork process is still running; aborting rather than layering a new client over it." >&2
    pgrep -a -x urnetwork || true
    exit 1
fi

echo
echo "[4/5] Installing latest official Linux provider (no auth, no start)..."
sh "$TMP_INSTALL" --no-start --no-modify-bashrc

echo
echo "[5/5] Verifying fresh installation..."
if [ ! -x "$INSTALL_PATH/bin/urnet-tools" ] || [ ! -x "$INSTALL_PATH/bin/urnetwork" ] || [ ! -s "$INSTALL_PATH/.version" ]; then
    echo "Fresh installation verification failed." >&2
    exit 1
fi
if [ -e "$STATE_DIR" ]; then
    echo "Unexpected identity directory exists after install; inspect before proceeding." >&2
    exit 1
fi
if systemctl --user is-active --quiet urnetwork.service 2>/dev/null; then
    echo "Provider unexpectedly started; stopping it." >&2
    systemctl --user stop urnetwork.service
fi

echo "Installed version: $(cat "$INSTALL_PATH/.version")"
echo "Old JWT and identity directory: DELETED"
echo "Provider service: stopped"
echo
echo "SUCCESS: old URnetwork client, services and identity removed; fresh official client installed."
echo "Authenticate this server with: $INSTALL_PATH/bin/urnetwork auth"
echo "Then start it with: $INSTALL_PATH/bin/urnet-tools start"
