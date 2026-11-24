# Sentinel dVPN Manager bundle

The ZIP is stored as base64 text so it can be retrieved from GitHub's raw file host and reconstructed byte-for-byte.

Pinned bundle commit: 35c81b6c67eef24ab891bdd9f0d8882b355baa60

Download and unpack on a fresh Debian/Ubuntu VPS:

```bash
sudo apt-get update
sudo apt-get install -y curl ca-certificates unzip
curl -fsSL https://raw.githubusercontent.com/TEST11R/arc-installers/35c81b6c67eef24ab891bdd9f0d8882b355baa60/downloads/Arcum-Sentinel-dVPN-Manager-Installer.zip.b64 | base64 -d > Arcum-Sentinel-dVPN-Manager-Installer.zip
unzip -o Arcum-Sentinel-dVPN-Manager-Installer.zip
sudo ./install.sh
```

Expected ZIP SHA-256:
`1114758ee901874de57eb30f19ce58eef39ffcbe0ce0aa7dcb79ee3aa9af2089`

Debian 13 (Trixie) uses the upstream source installer and is explicitly marked experimental because the upstream project documents generated packages for Debian 11/12, not Debian 13. The installer does not add an Ubuntu PPA to Debian 13.

Upstream project: https://github.com/sentinelgrowthdao/dvpn-node-manager

This installs/configures a new manager/node; it does not migrate an existing node, wallet, or keys.
