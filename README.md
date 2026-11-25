# Arcum Fleet Connector Installer

This repository contains the single-file Linux fleet installer for Arcum Connector 0.4.9.

## Install on each server

Run this single command on each target VPS (replace the token placeholder with the owner-issued bulk token):

```bash
curl -fsSL https://raw.githubusercontent.com/TEST11R/arc-installers/338587cd032d4751c0fbba47bd94e2b44d6542cd/arcum.sh -o /tmp/arcum.sh && sudo bash /tmp/arcum.sh 'YOUR_BULK_ENROLLMENT_TOKEN'
```

When already logged in as root, omit `sudo` before `bash`. The script also supports running without an argument and will prompt with terminal echo disabled. No API URL, hostname, IP, GitHub credential, or other option is required. Passing the token inline exposes it briefly in shell history and process arguments; use a short-lived bulk token and avoid shared multi-user hosts.

## Issue one fleet token in Arcum

Create one enrollment authority in the authenticated Arcum owner UI with:

- Mode: **bulk**
- Profile: **read_only**
- Maximum registrations: **100**
- Expiry: choose enough time to complete the rollout (for example, 24 hours)

Use that same bulk token on each target. The token authorizes joining only; every VPS receives its own server identity, connector identity, and permanent machine credential. Do not reuse the token as a machine credential.

## Central machine API

The installer is pinned to:

`https://96.62.250.27`

The public HTTPS gateway exposes only `GET /healthz` and the `/api/connector/*` machine routes. The private API remains bound to loopback on the Arcum host; the Admin and Operations panels remain separate.

## Requirements and safety

- Linux, systemd, Python 3.12 or newer, and outbound HTTPS.
- Requires root for the initial installation. If Python venv support is missing, the installer uses the system package manager to install it.
- The fleet connector runs under its own unprivileged `arcum-fleet-connector` account at `/var/lib/arcum-fleet-connector`; it does not overwrite the separate `arcum-connector` local test agent.

The installer is safe to rerun. If the machine is already enrolled, it reuses the existing permanent identity and does not consume another bulk registration. If its service is active, it leaves the process running; if stopped or failed, it enables/starts it. The user service is enabled for startup after reboot (via systemd lingering), restarts after process failure, and the agent retries network/API outages with backoff.
- Default enrollment authority is read-only; this installer does not enable host PTY, workspace execution, Docker management, or host filesystem access.
- The installer verifies the embedded archive SHA-256, pinned Ed25519 public-key fingerprint, per-file release checksums, and signed connector bundle before executing connector code.
- Existing `/var/lib/arcum-fleet-connector` data or an existing `arcum-fleet-connector` account causes a safe refusal; it does not overwrite an existing installation.
- The enrollment token is entered invisibly and is not written to the service environment file or shell arguments. The returned machine credential is stored in the private connector state file.

This installer is for the current Arcum Terminal API 0.4.0 / Connector 0.4.9 release. The public API pointer and signed payload must be updated together for future releases.


## Service recovery fix

The current pinned release writes valid unquoted `WorkingDirectory` and `EnvironmentFile` paths in the user service unit, and exits cleanly after completion. Rerunning the installer on an enrolled host reuses its existing read-only identity and reconciles the service without consuming another enrollment registration.


## URnetwork full clean reinstall

This is a destructive reset for the current Linux account. It removes the existing URnetwork provider client, matching systemd user/system services, the old JWT, and the full `~/.urnetwork` identity directory. It then installs the latest provider from URnetwork's official release feed. The new provider is left stopped and unauthenticated.

Run as the Linux account that owns the old provider (do not use `sudo`):

```bash
curl -fsSL https://raw.githubusercontent.com/TEST11R/arc-installers/7f2b51f4080992171a9947aff4cdf4628d7a730a/urnetwork/clean-install-urnetwork.sh | sh
```

**Warning:** this permanently deletes that server's local URnetwork identity/JWT. It does not affect identities on other servers or your URnetwork account. Authenticate the server again after installation:

```bash
urnetwork auth
urnet-tools start
urnet-tools status
```

The script checks that a legacy system-level service points to the exact URnetwork install path before removing it; unrelated systemd units are not touched.
