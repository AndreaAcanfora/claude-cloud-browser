# shellcheck shell=bash
# ufw: SSH only on a fresh server. On a server that already has a firewall
# (for example one that also serves websites) we only ADD the SSH rule and
# never remove or reset anything.
#
# Nothing else is opened: noVNC is reached through Tailscale (see 80-tailscale.sh).

step_firewall() {
  if ufw status | grep '^Status: active' >/dev/null; then
    log "ufw already active: shared-server mode, existing rules are kept"
    ufw allow 22/tcp comment 'SSH' >/dev/null
  else
    log "ufw inactive: fresh-server mode, allowing SSH only"
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null
    ufw allow 22/tcp comment 'SSH' >/dev/null
    ufw --force enable >/dev/null
  fi
  ok "ufw active, SSH allowed"
}
