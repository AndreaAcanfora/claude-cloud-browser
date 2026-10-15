# Architecture

## Components

| Component | Runs as | Listens on | Started by |
|---|---|---|---|
| `cb-xvfb` | `claude` (systemd user unit) | X display `:99`, unix socket only | user systemd (lingering) |
| `cb-chrome` | `claude` | DevTools `127.0.0.1:9222` | user systemd, after `cb-xvfb` |
| `cb-x11vnc` | `claude` | `127.0.0.1:5900` | user systemd, after `cb-xvfb` |
| `cb-novnc` (websockify + noVNC) | `claude` | `127.0.0.1:6080` | user systemd, after `cb-x11vnc` |
| `cb-remote-control` | `claude` | outbound only (Anthropic) | user systemd, after `cb-chrome`; skipped until logged in + `~/workspace` trusted |
| `cb-guard` | root (system unit) | nftables table `inet claude_cloud_browser` | system systemd |
| `tailscaled` + `tailscale serve` | root | tailnet HTTPS → `127.0.0.1:6080` | system systemd |
| Claude Code + Playwright MCP | `claude` | stdio | you, over SSH |

User units run under the `claude` user's own systemd instance. Lingering keeps it alive without an open session,
so the browser survives logouts and reboots, and `cb restart` / `cb logs` need no sudo.

## Why CDP

Playwright MCP normally launches its own fresh browser. With `--cdp-endpoint http://127.0.0.1:9222` it attaches
to the always-on Chrome instead, so Claude sees the same tabs, cookies and logins you created through noVNC.

## Installer layout

`install.sh` loads configuration (environment, `.env`, `/etc/claude-cloud-browser/install.env`) and runs the steps in
`lib/NN-<step>.sh` in order. Every step is idempotent: files are written only when their content changes, services are
restarted only when their unit changed. `--only <step,...>` re-runs selected steps.

| Step | Does |
|---|---|
| `system` | base packages, dedicated user + lingering, swap, unattended-upgrades, fail2ban |
| `firewall` | ufw: SSH only on a fresh server, additive on a server that already has rules |
| `ssh` | user's `authorized_keys`, key-only sshd drop-in with lockout protection |
| `claude` | per-user Node LTS (system Node untouched) + Claude Code from npm |
| `shell` | tmux + auto-attach of interactive SSH logins to session `main` (opt out with `~/.no-tmux`) |
| `browser` | Chrome (x86-64) or Playwright Chromium + AppArmor profile (ARM64), X cookie, resource cap, Xvfb + Chrome units |
| `mcp` | Playwright MCP registered in Claude Code (user scope) with `--cdp-endpoint` |
| `novnc` | VNC password, nftables port guard, x11vnc + noVNC units |
| `tailscale` | official package; once you ran `tailscale up`: operator + `tailscale serve` |
| `remote` | `~/workspace` + `CLAUDE.md`, always-on Remote Control unit (waits for your login and trust) |
| `cb` | `/usr/local/bin/cb` and its config |

## Separation from provisioning

The installer only configures the machine it runs on. Creating machines (Hetzner API, Stripe) belongs to a separate
provisioning layer that will pass configuration through cloud-init. See [../provisioning/README.md](../provisioning/README.md).
