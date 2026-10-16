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

  local target="http://127.0.0.1:$CB_NOVNC_PORT" port published=no
  # Ports where noVNC is published now (an older install may have used 443).
  for port in $(tailscale serve status --json 2>/dev/null |
    jq -r --arg t "$target" '.Web // {} | to_entries[]
      | select([.value.Handlers[]?.Proxy] | index($t)) | .key | sub(".*:"; "")'); do
    if [[ $port == "$CB_TS_HTTPS_PORT" ]]; then
      published=yes
    else
      log "moving noVNC off tailnet HTTPS port $port"
      tailscale serve --https="$port" off
    fi
  done

  if [[ $published == yes ]]; then
    ok "noVNC already published on the tailnet (HTTPS port $CB_TS_HTTPS_PORT)"
  else
    # On a new tailnet, serve waits forever for the admin to enable HTTPS:
    # bound it and show Tailscale's message (it contains the enable link).
    local out
    if out=$(timeout 30 tailscale serve --bg --https="$CB_TS_HTTPS_PORT" "$target" 2>&1); then
      ok "noVNC published on the tailnet (HTTPS port $CB_TS_HTTPS_PORT)"
    else
      warn "tailscale serve did not complete:"
      printf '%s\n' "$out" >&2
      warn "enable it with the link above, then re-run: sudo bash install.sh --only tailscale"
    fi
  fi
}
