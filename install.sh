#!/usr/bin/env bash
# claude-cloud-browser installer.
#
# Turns an Ubuntu 24.04 server into "Claude Code + an always-on Chrome":
# Claude Code drives the browser through Playwright MCP over CDP, and you
# see/use the same browser from your phone through noVNC over Tailscale.
#
# Idempotent: re-run it at any time, it only changes what is missing or
# out of date. Works as a cloud-init runcmd too (see cloud-init/).
#
# Usage:
#   sudo bash install.sh                 # every step
#   sudo bash install.sh --only browser  # one or more steps (comma separated)
#   sudo bash install.sh --list          # list the steps
#
# Configuration comes from the environment, from .env next to this script
# and from /etc/claude-cloud-browser/install.env (see .env.example).
# The installer never asks for, stores or transmits any credential:
# you log in to Claude and Tailscale yourself afterwards.

set -euo pipefail

CB_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export CB_ROOT

# shellcheck source=lib/common.sh
. "$CB_ROOT/lib/common.sh"

load_env_file() {
  [[ -f $1 ]] || return 0
  set -a
  # shellcheck disable=SC1090
  . "$1"
  set +a
}
load_env_file /etc/claude-cloud-browser/install.env
load_env_file "$CB_ROOT/.env"

: "${CB_USER:=claude}"
: "${CB_SSH_PUBKEY:=}"
: "${CB_COPY_ROOT_KEYS:=no}"
: "${CB_HARDEN_SSH:=auto}"
: "${CB_SWAP_GB:=4}"
: "${CB_MEMORY_MAX:=3G}"
: "${CB_CPU_QUOTA:=200%}"
: "${CB_DISPLAY:=:99}"
: "${CB_SCREEN:=1280x800x24}"
: "${CB_CDP_PORT:=9222}"
: "${CB_VNC_PORT:=5900}"
: "${CB_NOVNC_PORT:=6080}"
: "${CB_TS_HOSTNAME:=claude-vps}"
: "${CB_TS_HTTPS_PORT:=443}"
: "${CB_NODE_VERSION:=lts}"
: "${CB_PLAYWRIGHT_VERSION:=1.64.1}"
: "${CB_PLAYWRIGHT_MCP_VERSION:=0.0.83}"
: "${CB_RC_NAME:=$CB_TS_HOSTNAME}"
: "${CB_RC_PERMISSION_MODE:=default}"
export CB_USER CB_SSH_PUBKEY CB_COPY_ROOT_KEYS CB_HARDEN_SSH CB_SWAP_GB CB_MEMORY_MAX \
  CB_CPU_QUOTA CB_DISPLAY CB_SCREEN CB_CDP_PORT CB_VNC_PORT CB_NOVNC_PORT CB_TS_HOSTNAME \
  CB_TS_HTTPS_PORT CB_NODE_VERSION CB_PLAYWRIGHT_VERSION CB_PLAYWRIGHT_MCP_VERSION \
  CB_RC_NAME CB_RC_PERMISSION_MODE

STEPS=(system firewall ssh claude shell browser mcp novnc tailscale remote cb)

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

only=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --only) only=${2:?--only needs a step list}; shift 2 ;;
    --list) printf '%s\n' "${STEPS[@]}"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

require_root
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 24.04 ]] ||
  warn "tested on Ubuntu 24.04 only, this is ${PRETTY_NAME:-unknown}"

run_step() {
  local step=$1 file
  file=$(ls "$CB_ROOT"/lib/[0-9][0-9]-"$step".sh)
  log "── step: $step"
  # shellcheck disable=SC1090
  . "$file"
  "step_$step"
}

if [[ -n $only ]]; then
  IFS=, read -r -a selected <<<"$only"
  for s in "${selected[@]}"; do
    [[ " ${STEPS[*]} " == *" $s "* ]] || die "unknown step: $s (see --list)"
    run_step "$s"
  done
else
  for s in "${STEPS[@]}"; do run_step "$s"; done
fi

ok "done. Run 'cb status' to check the services."
