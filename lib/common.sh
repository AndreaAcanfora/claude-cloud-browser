# shellcheck shell=bash
# Shared helpers for install.sh and the lib/NN-*.sh steps.
# All messages go to stderr, so $(...) only ever captures data.
# Every helper is idempotent: running it twice leaves the system unchanged.
# Never use `cmd | grep -q` here: with pipefail, grep exiting early can kill
# cmd with SIGPIPE and fail the pipeline. Use `grep ... >/dev/null` instead.

log()  { printf '\033[1;36m[cb]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[cb]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[cb] WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[cb] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "run as root (sudo bash install.sh)"
}

# amd64 | arm64
detect_arch() {
  dpkg --print-architecture
}

cb_uid() {
  id -u "$CB_USER"
}

cb_home() {
  getent passwd "$CB_USER" | cut -d: -f6
}

# Run a command as the dedicated user, with the environment that
# `systemctl --user` and the per-user Node install need.
as_user() {
  local uid home
  uid=$(cb_uid)
  home=$(cb_home)
  # --chdir: the installer usually runs from a root-only directory.
  runuser -u "$CB_USER" -- env --chdir="$home" \
    HOME="$home" \
    USER="$CB_USER" \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    PATH="$home/.local/bin:$home/.local/npm/bin:$home/.local/node/bin:/usr/local/bin:/usr/bin:/bin" \
    "$@"
}

user_systemctl() {
  as_user systemctl --user "$@"
}

# Install only the apt packages that are missing.
apt_install() {
  local missing=() pkg
  for pkg in "$@"; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep "install ok installed" >/dev/null || missing+=("$pkg")
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0
  log "apt install ${missing[*]}"
  if [[ -z ${CB_APT_UPDATED:-} ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    CB_APT_UPDATED=1
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null
}

# ensure_file PATH MODE OWNER < content
# Writes stdin to PATH only when the content differs. Returns 0 if the file
# changed, 1 if it was already up to date (use it as `if ensure_file ...`).
ensure_file() {
  local path=$1 mode=$2 owner=$3 tmp
  tmp=$(mktemp)
  cat >"$tmp"
  if [[ -f $path ]] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"
    chmod "$mode" "$path"
    chown "$owner" "$path"
    return 1
  fi
  install -D -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$tmp" "$path"
  rm -f "$tmp"
  log "wrote $path"
  return 0
}

# ensure_line FILE LINE: append LINE to FILE unless it is already there.
ensure_line() {
  local file=$1 line=$2
  touch "$file"
  grep -qxF -- "$line" "$file" || { printf '%s\n' "$line" >>"$file"; log "updated $file"; }
}

# render TEMPLATE: print a template with @VAR@ placeholders filled in.
render() {
  sed -e "s|@CB_USER@|$CB_USER|g" \
      -e "s|@CB_HOME@|$(cb_home)|g" \
      -e "s|@CB_UID@|$(cb_uid)|g" \
      -e "s|@CB_DISPLAY@|$CB_DISPLAY|g" \
      -e "s|@CB_SCREEN@|$CB_SCREEN|g" \
      -e "s|@CB_WINDOW_SIZE@|$(cut -dx -f1,2 <<<"$CB_SCREEN" | tr x ,)|g" \
      -e "s|@CB_CDP_PORT@|$CB_CDP_PORT|g" \
      -e "s|@CB_VNC_PORT@|$CB_VNC_PORT|g" \
      -e "s|@CB_NOVNC_PORT@|$CB_NOVNC_PORT|g" \
      -e "s|@CB_MEMORY_MAX@|$CB_MEMORY_MAX|g" \
      -e "s|@CB_CPU_QUOTA@|$CB_CPU_QUOTA|g" \
      -e "s|@CB_RC_NAME@|$CB_RC_NAME|g" \
      -e "s|@CB_RC_PERMISSION_MODE@|$CB_RC_PERMISSION_MODE|g" \
      "$1"
}

# install_user_unit NAME: render systemd/user/NAME into the user's unit dir.
# Returns 0 if the unit file changed.
install_user_unit() {
  local name=$1 home
  home=$(cb_home)
  render "$CB_ROOT/systemd/user/$name" | ensure_file "$home/.config/systemd/user/$name" 644 "$CB_USER:$CB_USER"
}

# enable_user_unit NAME CHANGED: enable + start, restart if its file changed.
enable_user_unit() {
  local name=$1 changed=$2
  user_systemctl daemon-reload
  user_systemctl enable --quiet "$name"
  if [[ $changed == 1 ]]; then
    user_systemctl restart "$name"
  elif ! user_systemctl is-active --quiet "$name"; then
    user_systemctl start "$name"
  fi
}

# resolve_ts_https_port: turn CB_TS_HTTPS_PORT=auto into a port number.
# tailscaled binds the tailnet IP on the serve port at boot, before most
# services, so a web server that binds *:443 (Caddy, nginx, ...) would fail
# to start after the next reboot. Use 443 only when nothing else wants it.
resolve_ts_https_port() {
  [[ $CB_TS_HTTPS_PORT == auto ]] || return 0
  local other=no unit
  if ss -Hltnp 'sport = :443' 2>/dev/null | grep -v '"tailscaled"' | grep . >/dev/null; then
    other=yes
  fi
  for unit in caddy nginx apache2 httpd haproxy traefik lighttpd; do
    systemctl is-enabled --quiet "$unit" 2>/dev/null && other=yes
  done
  if [[ $other == yes ]]; then
    CB_TS_HTTPS_PORT=8443
  else
    CB_TS_HTTPS_PORT=443
  fi
}
