# shellcheck shell=bash
# The `cb` helper command and its config file.

step_cb() {
  ensure_file /etc/claude-cloud-browser/cb.conf 644 root:root <<EOF || true
# Managed by claude-cloud-browser (written by install.sh). Read by /usr/local/bin/cb.
CB_USER=$CB_USER
CB_CDP_PORT=$CB_CDP_PORT
CB_NOVNC_PORT=$CB_NOVNC_PORT
CB_TS_HTTPS_PORT=$CB_TS_HTTPS_PORT
EOF
  ensure_file /usr/local/bin/cb 755 root:root <"$CB_ROOT/bin/cb" || true
  ok "cb command installed (cb status | browser | restart | logs)"
}
