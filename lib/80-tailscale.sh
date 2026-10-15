# shellcheck shell=bash
# Tailscale: the only way to reach noVNC. Installs the official package and,
# once you have run `tailscale up` yourself, publishes noVNC on your tailnet
# over HTTPS with `tailscale serve` (tailnet only, never Funnel/public).

step_tailscale() {
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ ! -f /etc/apt/sources.list.d/tailscale.list ]]; then
    log "adding the Tailscale apt repository"
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" \
      -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.tailscale-keyring.list" \
      -o /etc/apt/sources.list.d/tailscale.list
    # shellcheck disable=SC2034  # read by apt_install (lib/common.sh)
    CB_APT_UPDATED=  # force apt-get update for the new repository
  fi
  apt_install tailscale
  systemctl enable --quiet --now tailscaled

  if [[ $(tailscale status --json 2>/dev/null | jq -r '.BackendState') != Running ]]; then
    warn "Tailscale is installed but not logged in. Run:"
    warn "  sudo tailscale up --hostname=$CB_TS_HOSTNAME"
    warn "then publish noVNC with: sudo bash install.sh --only tailscale"
    return 0
  fi

  # Lets the dedicated user run `tailscale serve` / `cb browser` without sudo.
  tailscale set --operator="$CB_USER"

  local target="http://127.0.0.1:$CB_NOVNC_PORT"
  if tailscale serve status --json 2>/dev/null |
    jq -e --arg t "$target" '[.. | .Proxy? // empty] | index($t)' >/dev/null; then
    ok "noVNC already published on the tailnet"
  else
    tailscale serve --bg --https="$CB_TS_HTTPS_PORT" "$target" >/dev/null
    ok "noVNC published on the tailnet (HTTPS port $CB_TS_HTTPS_PORT)"
  fi
}
