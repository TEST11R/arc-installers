#!/bin/sh
# Arcum URnetwork FULL CLEAN REINSTALL
# Pre-downloads and verifies the provider archive BEFORE deleting the old
# client/JWT, then uses URnetwork's official installer against local metadata.
set -eu

# Large provider archives must not be constrained by an inherited shell file-size limit.
ulimit -f unlimited || {
    echo "Unable to remove the shell file-size limit; refusing to start the large archive download." >&2
    exit 1
}

# Do not rely on the host's potentially tiny /tmp tmpfs.
TMP_BASE="${URNETWORK_TMPDIR:-/var/tmp/arcum-urnetwork}"
mkdir -p "$TMP_BASE"
chmod 700 "$TMP_BASE"
TMPDIR="$TMP_BASE"
export TMPDIR

INSTALL_URL="https://raw.githubusercontent.com/urnetwork/connect/main/scripts/Provider_Install_Linux.sh"
UNINSTALL_URL="https://raw.githubusercontent.com/urnetwork/connect/main/scripts/Provider_Uninstall_Linux.sh"
RELEASE_METADATA_URL="https://raw.githubusercontent.com/TEST11R/arc-installers/cf77bdcff31e4e8029ac7c1aa9d3d273da9d6233/urnetwork/upstream-api/releases/latest"
INSTALL_PATH="${URNETWORK_INSTALL_PATH:-$HOME/.local/share/urnetwork-provider}"
STATE_DIR="$HOME/.urnetwork"
TIMER_STAMP="$HOME/.local/share/systemd/timers/stamp-urnetwork-update.timer"
TMP_DIR="$(mktemp -d "$TMP_BASE/clean.XXXXXX")"
TMP_INSTALL="$TMP_DIR/Provider_Install_Linux.sh"
TMP_UNINSTALL="$TMP_DIR/Provider_Uninstall_Linux.sh"
TMP_METADATA="$TMP_DIR/release.json"
TMP_ARCHIVE="$TMP_DIR/urnetwork-provider.tar.gz"
TMP_API="$TMP_DIR/api"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    echo "Run as the account that owns the URnetwork provider, not through sudo." >&2
    exit 1
fi
command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for release metadata validation." >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required for release verification." >&2; exit 1; }

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

echo "[1/6] Fetching official installer, uninstaller and pinned release metadata..."
curl -fsSL "$UNINSTALL_URL" -o "$TMP_UNINSTALL"
curl -fsSL "$INSTALL_URL" -o "$TMP_INSTALL"
curl -fsSL "$RELEASE_METADATA_URL" -o "$TMP_METADATA"
grep -q 'SCRIPT_VERSION=' "$TMP_UNINSTALL" || { echo "Uninstaller validation failed." >&2; exit 1; }
grep -q 'api.github.com/repos/urnetwork/build' "$TMP_INSTALL" || { echo "Installer validation failed." >&2; exit 1; }

echo
echo "[2/6] Downloading and verifying the provider archive BEFORE removing anything..."
python3 - "$TMP_METADATA" "$TMP_ARCHIVE" "$TMP_API/releases/latest" <<'PY'
import json, pathlib, re, sys
metadata_path, archive_path, output_path = sys.argv[1:]
data = json.load(open(metadata_path, encoding="utf-8"))
tag = data.get("tag_name", "")
if not re.fullmatch(r"v[0-9A-Za-z._-]+", tag):
    raise SystemExit("Invalid or missing release tag in cached metadata")
assets = data.get("assets") or []
matches = [a for a in assets if re.fullmatch(r"urnetwork-provider-.+\.tar\.gz", a.get("name", ""))]
if len(matches) != 1:
    raise SystemExit("Expected exactly one provider archive in release metadata")
asset = matches[0]
digest = asset.get("digest", "")
if not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
    raise SystemExit("Release metadata is missing a valid SHA-256 digest")
if not asset.get("browser_download_url", "").startswith("https://github.com/urnetwork/build/releases/download/"):
    raise SystemExit("Provider archive URL is not an official URnetwork GitHub release URL")
pathlib.Path(output_path).parent.mkdir(parents=True, exist_ok=True)
local = pathlib.Path(archive_path).resolve().as_uri()
local_metadata = {
    "tag_name": tag,
    "assets": [{
        "name": asset["name"],
        "browser_download_url": local,
        "digest": digest
    }]
}
pathlib.Path(output_path).write_text(json.dumps(local_metadata), encoding="utf-8")
print("Verified release metadata:", tag)
print("Provider asset:", asset["name"])
print("Expected SHA256:", digest.split(":", 1)[1])
print("Local metadata prepared for official installer")
PY

ASSET_URL="$(python3 - "$TMP_METADATA" <<'PY'
import json, re, sys
x=json.load(open(sys.argv[1], encoding="utf-8"))
a=[a for a in x.get("assets",[]) if re.fullmatch(r"urnetwork-provider-.+\.tar\.gz",a.get("name",""))]
print(a[0]["browser_download_url"])
PY
)"
EXPECTED_SHA256="$(python3 - "$TMP_METADATA" <<'PY'
import json, re, sys
x=json.load(open(sys.argv[1], encoding="utf-8"))
a=[a for a in x.get("assets",[]) if re.fullmatch(r"urnetwork-provider-.+\.tar\.gz",a.get("name",""))]
print(a[0]["digest"].split(":",1)[1])
PY
)"
curl -fL --retry 3 --retry-delay 2 "$ASSET_URL" -o "$TMP_ARCHIVE"
ACTUAL_SHA256="$(sha256sum "$TMP_ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo "Provider archive checksum mismatch; old client and identity were NOT touched." >&2
    exit 1
fi
echo "Provider archive SHA-256 verified: $ACTUAL_SHA256"

echo
echo "[3/6] Stopping and removing legacy services, client and identity..."
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
echo "[4/6] Verifying old identity and running provider are gone..."
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
echo "[5/6] Installing verified release with URnetwork's official installer (no auth, no start)..."
URNETWORK_API_BASE="file://$TMP_API" sh "$TMP_INSTALL" --no-start --no-modify-bashrc

echo
echo "[6/6] Verifying fresh installation..."
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
