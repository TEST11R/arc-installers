# Foxinou Sentinel dVPN PPA — offline source configuration

PPA: `ppa:foxinou/dvpn-node-manager`

Launchpad archive signing-key fingerprint: `1E4DCBDC436F95468F1FEB793B604A1F5EE3D8E5`.

Key: `foxinou-dvpn-node-manager.asc`

Install the key locally:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
sudo gpg --dearmor --yes -o /etc/apt/keyrings/foxinou-dvpn-node-manager.gpg foxinou-dvpn-node-manager.asc
sudo chmod 0644 /etc/apt/keyrings/foxinou-dvpn-node-manager.gpg
```

Copy exactly one matching source file to `/etc/apt/sources.list.d/foxinou-dvpn-node-manager.list`:
- Ubuntu 24.04 Noble: `ubuntu-noble.list`
- Debian 11 Bullseye: `debian11.list` (PPA suite `focal`)
- Debian 12 Bookworm: `debian12.list` (PPA suite `jammy`)

Then, when online, run `sudo apt-get update`. This bundle contains the signing key and source entries, not the PPA's `.deb` packages or dependencies. Adding a source entry offline does not make package installation offline. Debian 13 is not included because upstream has not documented it in the PPA package matrix.
