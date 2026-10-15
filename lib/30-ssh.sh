# shellcheck shell=bash
# SSH keys for the dedicated user and key-only login.
#
# Safety net: password login is disabled only when BOTH the dedicated user
# and root already have at least one key in authorized_keys, so a re-run can
# never lock you out of the server.

SSH_DROPIN=/etc/ssh/sshd_config.d/10-claude-cloud-browser.conf

step_ssh() {
  local home keys
  home=$(cb_home)
  keys="$home/.ssh/authorized_keys"
  runuser -u "$CB_USER" -- touch "$keys"
  chmod 600 "$keys"

  if [[ -n $CB_SSH_PUBKEY ]]; then
    [[ $CB_SSH_PUBKEY =~ ^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh.com)\ AAAA[0-9A-Za-z+/]+=*(\ .*)?$ ]] ||
      die "CB_SSH_PUBKEY does not look like an OpenSSH public key"
    ensure_line "$keys" "$CB_SSH_PUBKEY"
  fi
  if [[ $CB_COPY_ROOT_KEYS == yes && -s /root/.ssh/authorized_keys ]]; then
    local line
    while IFS= read -r line; do
      [[ -z $line || $line == \#* ]] && continue
      ensure_line "$keys" "$line"
    done </root/.ssh/authorized_keys
  fi
  chown "$CB_USER:$CB_USER" "$keys"

  case $CB_HARDEN_SSH in
    no) warn "CB_HARDEN_SSH=no: password login left as it is"; return 0 ;;
    auto|yes) ;;
    *) die "CB_HARDEN_SSH must be auto, yes or no" ;;
  esac

  if ! has_key "$keys"; then
    warn "$CB_USER has no SSH key yet: password login NOT disabled."
    warn "Set CB_SSH_PUBKEY='ssh-ed25519 ...' and re-run: sudo bash install.sh --only ssh"
    return 0
  fi
  if ! has_key /root/.ssh/authorized_keys; then
    warn "root has no SSH key: password login NOT disabled, to avoid locking root out."
    return 0
  fi

  if ensure_file "$SSH_DROPIN" 644 root:root <<'EOF'; then
# Managed by claude-cloud-browser. Key-only SSH.
# This file sorts before 50-cloud-init.conf, and sshd keeps the first value it reads.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
    if ! sshd -t; then
      rm -f "$SSH_DROPIN"
      die "sshd config test failed, drop-in removed"
    fi
    systemctl reload ssh
  fi
  sshd -T 2>/dev/null | grep -x 'passwordauthentication no' >/dev/null ||
    die "password login is still enabled; check /etc/ssh/sshd_config and its includes"
  ok "SSH: key-only login"
}

has_key() {
  # A key line may start with options (from="...",no-pty ssh-ed25519 ...).
  [[ -s $1 ]] && grep -qE '(^|[ ,"])(ssh-(ed25519|rsa|dss)|ecdsa-sha2-|sk-ssh-|sk-ecdsa-)[^ ]* AAAA' "$1"
}
