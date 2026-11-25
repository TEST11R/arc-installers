#!/bin/sh
# Arcum URnetwork FULL CLEAN REINSTALL
# Removes the current user's URnetwork client, services, JWT and local identity,
# then installs the latest official Linux provider without starting it.
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

# Make the current user's systemd manager reachable in non-interactive SSH runs.
if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -S "/run/user/$(id -u)/bus" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
fi

echo "URnetwork FULL clean reinstall"
echo "Host: $(hostname)"
echo "Provider user: $(id -un)"
echo "Install path: $INSTALL_PATH"
echo "Identity path to DELETE: $STATE_DIR"
echo

echo "[1/5] Fetching official upstream uninstall/install scripts..."
curl -fsSL "$UNINSTALL_URL" -o "$TMP_UNINSTALL"
curl -fsSL "$INSTALL_URL" -o "$TMP_INSTALL"
grep -q 'SCRIPT_VERSION=' "$TMP_UNINSTALL" || { echo "Uninstaller validation failed." >&2; exit 1; }
grep -q 'api.github.com/repos/urnetwork/build' "$TMP_INSTALL" || { echo "Installer validation failed." >&2; exit 1; }

echo
echo "[2/5] Stopping provider and removing old client, service units and identity..."
# Older provider deployments may have a manually-created system-level unit
# rather than urnet-tools' marked --system unit. Remove it only when its
# Description and ExecStart match this exact URnetwork install path.
if [ -f /etc/systemd/system/urnetwork.service ] &&
   grep -q '^Description=URnetwork Provider
    TOOLS=""
    if command -v urnet-tools >/dev/null 2>&1; then TOOLS="$(command -v urnet-tools)"
    elif [ -x "$INSTALL_PATH/bin/urnet-tools" ]; then TOOLS="$INSTALL_PATH/bin/urnet-tools"
    fi
    if [ -z "$TOOLS" ]; then
        echo "A URnetwork system service exists but urnet-tools is missing; refusing unsafe partial removal." >&2
        exit 1
    fi
    "$TOOLS" uninstall --remove-identity --yes --no-modify-bashrc
else
    sh "$TMP_UNINSTALL" --dest "$INSTALL_PATH" --remove-identity --no-modify-bashrc
fi

# Remove only the known URnetwork update timer stamp, if the old release left it behind.
rm -f "$TIMER_STAMP"

echo
echo "[3/5] Confirming old URnetwork state is gone..."
if [ -e "$INSTALL_PATH" ] || [ -e "$STATE_DIR" ]; then
    echo "Old install or identity directory remains; stopping before reinstall." >&2
    ls -ld "$INSTALL_PATH" "$STATE_DIR" 2>/dev/null || true
    exit 1
fi
if systemctl --user is-active --quiet urnetwork.service 2>/dev/null; then
    echo "Old URnetwork service is still active; refusing to install over it." >&2
    exit 1
fi

echo
echo "[4/5] Installing latest official Linux provider (no auth, no start)..."
sh "$TMP_INSTALL" --no-start --no-modify-bashrc

echo
echo "[5/5] Verifying fresh install and empty identity..."
if [ ! -x "$INSTALL_PATH/bin/urnet-tools" ] || [ ! -x "$INSTALL_PATH/bin/urnetwork" ] || [ ! -s "$INSTALL_PATH/.version" ]; then
    echo "Fresh installation verification failed." >&2
    exit 1
fi
if [ -e "$STATE_DIR" ]; then
    echo "Unexpected identity directory exists after clean install; inspect before proceeding." >&2
    exit 1
fi
if systemctl --user is-active --quiet urnetwork.service 2>/dev/null; then
    echo "Provider unexpectedly started; stopping it." >&2
    systemctl --user stop urnetwork.service
fi

echo "Installed version: $(cat "$INSTALL_PATH/.version")"
echo "Old JWT and ~/.urnetwork identity: DELETED"
echo "Provider service: stopped"
echo
echo "SUCCESS: old URnetwork client and identity removed; fresh official client installed."
echo "Authenticate this server with: $INSTALL_PATH/bin/urnetwork auth"
echo "Then start it with: $INSTALL_PATH/bin/urnet-tools start"
 /etc/systemd/system/urnetwork.service &&
   grep -Fq "ExecStart=$INSTALL_PATH/bin/urnetwork provide" /etc/systemd/system/urnetwork.service; then
    systemctl disable --now urnetwork.service
    rm -f /etc/systemd/system/urnetwork.service
    systemctl daemon-reload
    systemctl reset-failed urnetwork.service 2>/dev/null || true
elif [ -f /etc/systemd/system/urnetwork.service ] &&
   grep -q '^# Installed by urnet-tools --system' /etc/systemd/system/urnetwork.service 2>/dev/null; then
    TOOLS=""
    if command -v urnet-tools >/dev/null 2>&1; then TOOLS="$(command -v urnet-tools)"
    elif [ -x "$INSTALL_PATH/bin/urnet-tools" ]; then TOOLS="$INSTALL_PATH/bin/urnet-tools"
    fi
    if [ -z "$TOOLS" ]; then
        echo "A URnetwork system service exists but urnet-tools is missing; refusing unsafe partial removal." >&2
        exit 1
    fi
    "$TOOLS" uninstall --remove-identity --yes --no-modify-bashrc
else
    sh "$TMP_UNINSTALL" --dest "$INSTALL_PATH" --remove-identity --no-modify-bashrc
fi

# Remove only the known URnetwork update timer stamp, if the old release left it behind.
rm -f "$TIMER_STAMP"

echo
echo "[3/5] Confirming old URnetwork state is gone..."
if [ -e "$INSTALL_PATH" ] || [ -e "$STATE_DIR" ]; then
    echo "Old install or identity directory remains; stopping before reinstall." >&2
    ls -ld "$INSTALL_PATH" "$STATE_DIR" 2>/dev/null || true
    exit 1
fi
if systemctl --user is-active --quiet urnetwork.service 2>/dev/null; then
    echo "Old URnetwork service is still active; refusing to install over it." >&2
    exit 1
fi

echo
echo "[4/5] Installing latest official Linux provider (no auth, no start)..."
sh "$TMP_INSTALL" --no-start --no-modify-bashrc

echo
echo "[5/5] Verifying fresh install and empty identity..."
if [ ! -x "$INSTALL_PATH/bin/urnet-tools" ] || [ ! -x "$INSTALL_PATH/bin/urnetwork" ] || [ ! -s "$INSTALL_PATH/.version" ]; then
    echo "Fresh installation verification failed." >&2
    exit 1
fi
if [ -e "$STATE_DIR" ]; then
    echo "Unexpected identity directory exists after clean install; inspect before proceeding." >&2
    exit 1
fi
if systemctl --user is-active --quiet urnetwork.service 2>/dev/null; then
    echo "Provider unexpectedly started; stopping it." >&2
    systemctl --user stop urnetwork.service
fi

echo "Installed version: $(cat "$INSTALL_PATH/.version")"
echo "Old JWT and ~/.urnetwork identity: DELETED"
echo "Provider service: stopped"
echo
echo "SUCCESS: old URnetwork client and identity removed; fresh official client installed."
echo "Authenticate this server with: $INSTALL_PATH/bin/urnetwork auth"
echo "Then start it with: $INSTALL_PATH/bin/urnet-tools start"
