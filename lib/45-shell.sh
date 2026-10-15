# shellcheck shell=bash
# tmux with auto-attach on SSH login.
#
# Phones drop SSH connections all the time (iOS suspends Termius in the
# background). Every interactive SSH login of the dedicated user lands in
# the same tmux session, so a running `claude` survives the disconnect and
# is right there on the next login.
#
# Opt out for one login: create ~/.no-tmux (or set CB_NO_TMUX=1).

step_shell() {
  apt_install tmux

  local home
  home=$(cb_home)
  runuser -u "$CB_USER" -- mkdir -p "$home/.config/cb"

  ensure_file "$home/.config/cb/tmux-autoattach.sh" 644 "$CB_USER:$CB_USER" <<'EOF' || true
# Managed by claude-cloud-browser: attach every interactive SSH login to the
# "main" tmux session. Detach with Ctrl-b d (this also ends the SSH session).
if [[ $- == *i* && -n ${SSH_TTY:-} && -z ${TMUX:-} && -z ${CB_NO_TMUX:-} && ! -e $HOME/.no-tmux ]] &&
  command -v tmux >/dev/null; then
  exec tmux new-session -A -s main
fi
EOF

  # Phone-friendly defaults; written once, then the file is yours to edit.
  if [[ ! -e $home/.tmux.conf ]]; then
    runuser -u "$CB_USER" -- tee "$home/.tmux.conf" >/dev/null <<'EOF'
# Written by claude-cloud-browser on first install; edit freely.
set -g mouse on              # scroll and select panes with touch
set -g history-limit 50000   # long Claude transcripts
set -g default-terminal "tmux-256color"
set -sg escape-time 10       # snappy Esc in Claude Code
set -g status-right "#H  %H:%M"
EOF
    log "wrote $home/.tmux.conf"
  fi

  # Last line of .bashrc, after the PATH line, so claude is found inside tmux.
  # shellcheck disable=SC2016  # expanded by the user's shell, not here
  ensure_line "$home/.bashrc" '[ -f "$HOME/.config/cb/tmux-autoattach.sh" ] && . "$HOME/.config/cb/tmux-autoattach.sh"'
  chown "$CB_USER:$CB_USER" "$home/.bashrc"
  ok "tmux: SSH logins of $CB_USER attach to session 'main'"
}
