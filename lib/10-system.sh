# shellcheck shell=bash
# Dedicated non-root user, swap, unattended-upgrades, fail2ban, base packages.

step_system() {
  # libatomic1: the official Node arm64 binaries link against it, and a
  # fresh Ubuntu 24.04 cloud image does not ship it.
  apt_install ca-certificates curl git xz-utils jq dbus-user-session libatomic1 \
    unattended-upgrades fail2ban nftables ufw

  ensure_user
  ensure_swap
  ensure_unattended_upgrades

  systemctl enable --quiet --now fail2ban
  ok "fail2ban active"
}

ensure_user() {
  if ! id "$CB_USER" &>/dev/null; then
    useradd --create-home --shell /bin/bash "$CB_USER"
    log "created user $CB_USER"
  fi
  # No sudo: the user only owns its home, its services and its browser.
  if id -nG "$CB_USER" | tr ' ' '\n' | grep -xE 'sudo|admin|wheel' >/dev/null; then
    warn "$CB_USER is in an admin group; claude-cloud-browser expects it without sudo"
  fi

  local home uid
  home=$(cb_home)
  uid=$(cb_uid)
  chmod 750 "$home"
  runuser -u "$CB_USER" -- mkdir -p \
    "$home/.config/systemd/user" "$home/.local/bin" "$home/.ssh" "$home/.vnc"
  chmod 700 "$home/.ssh" "$home/.vnc"

  # Lingering keeps the user's systemd instance (and so the browser) running
  # without anyone logged in.
  if [[ ! -f /var/lib/systemd/linger/$CB_USER ]]; then
    loginctl enable-linger "$CB_USER"
    log "enabled lingering for $CB_USER"
  fi
  systemctl start "user@$uid.service"

  for _ in $(seq 1 20); do
    [[ -S /run/user/$uid/systemd/private ]] && break
    sleep 0.5
  done
  [[ -S /run/user/$uid/systemd/private ]] || die "user systemd instance for $CB_USER did not start"
}

# Make sure total swap is at least CB_SWAP_GB, adding /swapfile-cb for the gap.
ensure_swap() {
  local want_kb have_kb need_mb
  want_kb=$((CB_SWAP_GB * 1024 * 1024))
  have_kb=$(awk 'NR > 1 { s += $3 } END { print s + 0 }' /proc/swaps)
  if [[ -f /swapfile-cb ]]; then
    swapon --show=NAME --noheadings | grep -x /swapfile-cb >/dev/null || swapon /swapfile-cb
  elif ((have_kb < want_kb)); then
    need_mb=$(((want_kb - have_kb + 1023) / 1024))
    log "adding ${need_mb} MB of swap in /swapfile-cb"
    fallocate -l "${need_mb}M" /swapfile-cb
    chmod 600 /swapfile-cb
    mkswap -q /swapfile-cb
    swapon /swapfile-cb
  fi
  if [[ -f /swapfile-cb ]]; then
    ensure_line /etc/fstab "/swapfile-cb none swap sw 0 0"
  fi
  ok "swap total: $(awk 'NR > 1 { s += $3 } END { printf "%.1f GB", s / 1048576 }' /proc/swaps)"
}

ensure_unattended_upgrades() {
  ensure_file /etc/apt/apt.conf.d/20auto-upgrades 644 root:root <<'EOF' || true
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  systemctl enable --quiet --now unattended-upgrades
  ok "unattended-upgrades active"
}
