# Security model

claude-cloud-browser runs a browser that is **logged in to your accounts** and lets an AI agent drive it.
Everything below is about keeping that browser reachable only by you and by your Claude Code session.

## Threats and mitigations

| Threat | Mitigation |
|---|---|
| Brute force / credential stuffing on SSH | Key-only SSH (`PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin prohibit-password`), fail2ban `sshd` jail |
| Password login disabled before a key works (lockout) | The SSH step applies the drop-in only if both the dedicated user and root already have a key, then runs `sshd -t` and verifies the effective config with `sshd -T` |
| Someone on the internet opens noVNC | noVNC listens on `127.0.0.1` only and is published with `tailscale serve` (tailnet only, HTTPS, never Funnel). x11vnc has its own password |
| Another local user (a web app, a compromised service) attaches to the DevTools port and hijacks the logged-in sessions | The `cb-guard` service loads an nftables table that rejects loopback connections to the CDP, VNC and noVNC ports unless the socket owner is the dedicated user or root |
| Another local user reads or types into the X display | Xvfb runs with `-nolisten tcp -auth ~/.Xauthority`: only clients holding the user's cookie can connect |
| The browser or Claude eats all memory and takes down other services | A drop-in on `user-<uid>.slice` caps everything the user runs (`MemoryMax`, `CPUQuota`); swap is raised to at least 4 GB |
| Claude Code escalates to root | The dedicated user has no sudo and is not in any admin group; its home is `750` |
| Unpatched system packages | unattended-upgrades enabled |
| Browser sandbox disabled to make Chromium start on Ubuntu 24.04 | Not disabled. An AppArmor profile grants unprivileged user namespaces to the Playwright Chromium binary only, so the normal sandbox keeps working |
| Credentials leaked by the project | The installer never asks for or stores passwords, tokens or API keys. Claude and Tailscale logins are done by you, interactively |

## Residual risks (read these)

- **Prompt injection.** A web page can contain text that tries to instruct Claude. Keep a human in the loop for anything that spends money, sends messages or changes settings.
- **Root still controls everything.** Root can read the browser profile. On a shared server, trust root.
- **The ARM64 browser does not auto-update.** It is a pinned Playwright Chromium build. Bump `CB_PLAYWRIGHT_VERSION` and re-run `install.sh --only browser` regularly.
- **The VNC password is short** (VNC protocol limit, 8 characters). It is a second layer behind Tailscale, not the main one.
- **Tailscale is trusted.** Anyone in your tailnet can reach noVNC. Keep the tailnet personal, or restrict it with ACLs.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability reporting on this repository.
