# shellcheck shell=bash
# Browser on demand: with CB_CHROME_IDLE_STOP=<minutes> the browser stops after
# that long without use and starts again on the next DevTools or VNC
# connection (Playwright MCP, scripts, noVNC), with a 2-3 s wait. Logins
# survive, they live in the profile on disk.
#
# How: systemd keeps 127.0.0.1:CB_CDP_PORT and :CB_VNC_PORT open (socket
# units); the first connection starts cb-wake-proxy, which requires the
# browser and forwards to it on the backend ports, recording each use.
# cb-idle.timer checks every minute and stops the browser when unused.
#
# CB_CHROME_KEEP_AWAKE ("Mon..Fri 07:00-18:00", in CB_TIMEZONE) are hours when
# the browser stays up anyway, with CB_CHROME_KEEP_AWAKE_URLS kept open.

CB_LIBEXEC=/usr/local/lib/claude-cloud-browser

step_idle() {
  apt_install python3 jq curl

  ensure_file "$CB_LIBEXEC/cb-wake-proxy" 755 root:root <"$CB_ROOT/bin/cb-wake-proxy" || true
  ensure_file "$CB_LIBEXEC/cb-idle" 755 root:root <"$CB_ROOT/bin/cb-idle" || true
  write_idle_conf
  as_user "$CB_LIBEXEC/cb-idle" --check || die "fix the settings above and re-run: install.sh --only idle"

  if [[ $CB_CHROME_IDLE_STOP == off ]]; then
    remove_wake_units
    bind_browser_ports
    ok "browser always on (CB_CHROME_IDLE_STOP=off)"
  else
    # The browser and x11vnc must leave the usual ports before the sockets take them.
    bind_browser_ports
    local name changed
    for name in cb-cdp cb-vnc; do
      changed=0
      install_user_unit "$name-proxy.service" && changed=1
      install_user_unit "$name.socket" && changed=1
      user_systemctl daemon-reload
      if [[ $changed == 1 ]]; then
        user_systemctl stop "$name-proxy.service" 2>/dev/null || true
      fi
      enable_user_unit "$name.socket" "$changed"
    done
    ok "browser stops after $CB_CHROME_IDLE_STOP min unused and starts on the next use of 127.0.0.1:$CB_CDP_PORT or :$CB_VNC_PORT"
  fi

  ensure_idle_timer
}

write_idle_conf() {
  local v
  {
    echo "# Managed by claude-cloud-browser (written by install.sh). Read by cb-idle."
    for v in CB_CHROME_IDLE_STOP CB_CHROME_KEEP_AWAKE CB_CHROME_KEEP_AWAKE_URLS CB_TIMEZONE CB_CHROME_CDP_PORT; do
      printf '%s=%q\n' "$v" "${!v}"
    done
  } | ensure_file /etc/claude-cloud-browser/idle.conf 644 root:root || true
}

# Re-render the browser and x11vnc units for the current mode (their ports
# depend on it), restarting them only when that changed.
bind_browser_ports() {
  local changed=0
  install_user_unit cb-chrome.service && changed=1
  enable_user_unit cb-chrome.service "$changed"
  if [[ -f $(cb_home)/.config/systemd/user/cb-x11vnc.service ]]; then
    changed=0
    install_user_unit cb-x11vnc.service && changed=1
    enable_user_unit cb-x11vnc.service "$changed"
  fi
}

ensure_idle_timer() {
  local home changed=0
  home=$(cb_home)
  if [[ $CB_CHROME_IDLE_STOP == off && -z $CB_CHROME_KEEP_AWAKE ]]; then
    if [[ -f $home/.config/systemd/user/cb-idle.timer ]]; then
      user_systemctl disable --now --quiet cb-idle.timer 2>/dev/null || true
      rm -f "$home/.config/systemd/user/cb-idle.timer" "$home/.config/systemd/user/cb-idle.service"
      user_systemctl daemon-reload
    fi
    return 0
  fi
  install_user_unit cb-idle.service || true
  install_user_unit cb-idle.timer && changed=1
  enable_user_unit cb-idle.timer "$changed"
  if [[ -n $CB_CHROME_KEEP_AWAKE ]]; then
    ok "browser kept up: $CB_CHROME_KEEP_AWAKE${CB_TIMEZONE:+ ($CB_TIMEZONE)}${CB_CHROME_KEEP_AWAKE_URLS:+, with $CB_CHROME_KEEP_AWAKE_URLS}"
  fi
}
