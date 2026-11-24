# Sentinel dVPN Manager bundle

The ZIP is stored as base64 text so it can be retrieved from GitHub's raw file host and reconstructed byte-for-byte.

Pinned bundle commit: 12c498f640e6281ddf855690f6b3a0d534fbf6a6

Download and unpack:

```bash
curl -fsSL https://raw.githubusercontent.com/TEST11R/arc-installers/12c498f640e6281ddf855690f6b3a0d534fbf6a6/downloads/Arcum-Sentinel-dVPN-Manager-Installer.zip.b64 | base64 -d > Arcum-Sentinel-dVPN-Manager-Installer.zip
python3 -m zipfile -e Arcum-Sentinel-dVPN-Manager-Installer.zip .
sudo bash ./install.sh
```

Expected ZIP SHA-256:
`07b88654e9963e9dab70b572c3b935e83f2fd392e7ab0e6725f9e14b2b4a8584`

The installer automatically downloads and installs the Foxinou PPA signing key, writes a repository entry with a dedicated `signed-by` keyring, selects the correct suite, refreshes APT, and installs `dvpn-node-manager`.

Supported mappings documented by the upstream project:
- Ubuntu 20.04 Focal -> `focal`
- Ubuntu 22.04 Jammy -> `jammy`
- Ubuntu 24.04 Noble -> `noble`
- Debian 11 Bullseye -> `focal`
- Debian 12 Bookworm -> `jammy`

Debian 13 (Trixie) is rejected because it is not in the upstream PPA's documented package matrix. The installer does not force an Ubuntu PPA onto Debian 13.

If APT update fails because the VPS's base Debian repositories are broken, the installer stops before package installation and leaves those base sources untouched.

Upstream project and installation instructions: https://github.com/sentinelgrowthdao/dvpn-node-manager

This installs the manager package for a new node; it does not migrate an existing node, wallet, or keys.
