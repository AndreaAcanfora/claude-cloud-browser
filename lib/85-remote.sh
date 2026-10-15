# shellcheck shell=bash
# Claude Code Remote Control as an always-on service: use the Claude on this
# server from the Claude app or claude.ai/code, with no terminal open.
#
# Two things only you can do, once (the service waits for both):
#   1. log in to Claude:            claude
#   2. trust the workspace folder:  cd ~/workspace && claude   (accept, then /exit)
# Claude refuses to trust a home directory, hence the dedicated ~/workspace.

step_remote() {
  local home ws
  home=$(cb_home)
  ws="$home/workspace"
  runuser -u "$CB_USER" -- mkdir -p "$ws"

  # Written once, then it is yours: tells Claude what this machine offers.
  if [[ ! -e $ws/CLAUDE.md ]]; then
    runuser -u "$CB_USER" -- tee "$ws/CLAUDE.md" >/dev/null <<'MD'
# This machine

You run on a claude-cloud-browser server.

- The `playwright` MCP server controls an always-on Chrome with a persistent profile.
  The user has already logged in to their websites in that browser: reuse those sessions,
  do not log out, do not clear cookies.
- If a page needs a captcha, a 2FA code or a login, stop and ask the user to solve it
  through noVNC (they get the address with `cb browser`), then continue.
- Ask before anything that spends money, sends messages on the user's behalf or changes account settings.
MD
    log "wrote $ws/CLAUDE.md"
  fi

  local changed=0
  ensure_file "$home/.local/bin/cb-rc-ready" 755 "$CB_USER:$CB_USER" <"$CB_ROOT/bin/cb-rc-ready" && changed=1
  install_user_unit cb-remote-control.service && changed=1
  user_systemctl daemon-reload
  user_systemctl enable --quiet cb-remote-control.service

  if [[ ! -s $home/.claude/.credentials.json ]]; then
    warn "Remote Control waits for your Claude login. As $CB_USER run: claude"
    warn "then: cd ~/workspace && claude   (accept the trust prompt, then /exit), then: cb restart remote"
    return 0
  fi
  if ! as_user cb-rc-ready 2>/dev/null; then
    warn "Remote Control waits for you to trust $ws. As $CB_USER run:"
    warn "  cd ~/workspace && claude    (accept the trust prompt, then /exit), then: cb restart remote"
    return 0
  fi
  if [[ $changed == 1 ]] || ! user_systemctl is-active --quiet cb-remote-control.service; then
    user_systemctl restart cb-remote-control.service
  fi
  ok "Remote Control running as '$CB_RC_NAME' (Claude app > Code)"
}
