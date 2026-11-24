# Sentinel dVPN Manager bundle

The ZIP is stored as base64 text so it can be retrieved from GitHub's raw file host and reconstructed byte-for-byte.

Pinned bundle commit: d17dba8ae4dcfb5b7233c5fb20e7918974cb3184

Download and unpack on a fresh Ubuntu amd64 VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/TEST11R/arc-installers/d17dba8ae4dcfb5b7233c5fb20e7918974cb3184/downloads/Arcum-Sentinel-dVPN-Manager-Installer.zip.b64 | base64 -d > Arcum-Sentinel-dVPN-Manager-Installer.zip
unzip Arcum-Sentinel-dVPN-Manager-Installer.zip
sudo ./install.sh
```

Expected ZIP SHA-256:
`a5efe45ca9e76013ae910bc1018ced348ec354aa97bd0ee8018d6055964f88b6`

This installs the manager from its upstream PPA; it does not migrate any existing node, wallet, or keys.
