# shellcheck shell=bash
# x11vnc + noVNC (websockify) to see and use the browser from a phone.
# Both listen on 127.0.0.1 only; 80-tailscale.sh publishes noVNC on your
# tailnet. Nothing here is reachable from the internet.

step_novnc() {
  apt_install x11vnc novnc websockify

  ensure_vnc_password
  ensure_port_guard

  local changed=0
  install_user_unit cb-x11vnc.service && changed=1
  enable_user_unit cb-x11vnc.service "$changed"

  changed=0
  install_user_unit cb-novnc.service && changed=1
  enable_user_unit cb-novnc.service "$changed"

  ok "noVNC on 127.0.0.1:$CB_NOVNC_PORT"
}

# A second lock on top of Tailscale. VNC passwords are capped at 8 characters.
# The plain copy is readable only by the user, so `cb browser` can show it.
ensure_vnc_password() {
  local home pw
  home=$(cb_home)
  [[ -s $home/.vnc/passwd && -s $home/.vnc/password.txt ]] && return 0
  # No `tr </dev/urandom | head`: with pipefail the SIGPIPE on tr aborts the script.
  pw=$(head -c 256 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')
  pw=${pw:0:8}
  as_user x11vnc -quiet -storepasswd "$pw" "$home/.vnc/passwd" >/dev/null 2>&1
  printf '%s\n' "$pw" | runuser -u "$CB_USER" -- tee "$home/.vnc/password.txt" >/dev/null
  chmod 600 "$home/.vnc/passwd" "$home/.vnc/password.txt"
  log "generated VNC password (shown by: cb browser)"
}

ensure_port_guard() {
  local changed=0
  render "$CB_ROOT/systemd/system/guard.nft" |
    ensure_file /etc/claude-cloud-browser/guard.nft 644 root:root && changed=1
  render "$CB_ROOT/systemd/system/cb-guard.service" |
    ensure_file /etc/systemd/system/cb-guard.service 644 root:root && changed=1
  if [[ $changed == 1 ]]; then
    systemctl daemon-reload
    systemctl enable --quiet cb-guard.service
    systemctl restart cb-guard.service
  else
    systemctl enable --quiet --now cb-guard.service
  fi
  ok "local ports $CB_CDP_PORT/$CB_VNC_PORT/$CB_NOVNC_PORT reserved to $CB_USER and root"
}
