# shellcheck shell=bash
# The always-on browser: Xvfb (virtual display) + Chrome/Chromium in headful
# mode with a persistent profile and the DevTools port on 127.0.0.1 only.
#
# amd64: Google Chrome stable from Google's apt repo.
# arm64: Google ships no Linux ARM build, so we use Playwright's Chromium
#        (Ubuntu's own chromium is a snap, which does not play well with a
#        custom profile directory under systemd).

step_browser() {
  apt_install xvfb xauth fonts-liberation fonts-noto-color-emoji fonts-noto-cjk

  local bin
  case $(detect_arch) in
    amd64) bin=$(install_google_chrome) ;;
    arm64) bin=$(install_playwright_chromium) ;;
    *) die "unsupported architecture: $(detect_arch)" ;;
  esac
  local home
  home=$(cb_home)
  runuser -u "$CB_USER" -- ln -sfn "$bin" "$home/.local/bin/cb-browser"
  ok "browser: $bin"

  ensure_xauthority
  ensure_user_slice_limits

  local changed=0
  install_user_unit cb-xvfb.service && changed=1
  enable_user_unit cb-xvfb.service "$changed"

  changed=0
  install_user_unit cb-chrome.service && changed=1
  enable_user_unit cb-chrome.service "$changed"

  wait_for_cdp
}

install_google_chrome() {
  apt_install gnupg
  if [[ ! -f /etc/apt/sources.list.d/google-chrome.list ]]; then
    install -d -m 755 /etc/apt/keyrings
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor --yes -o /etc/apt/keyrings/google-chrome.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
      >/etc/apt/sources.list.d/google-chrome.list
    # shellcheck disable=SC2034  # read by apt_install (lib/common.sh)
    CB_APT_UPDATED=  # force apt-get update for the new repository
  fi
  apt_install google-chrome-stable
  echo /usr/bin/google-chrome-stable
}

install_playwright_chromium() {
  local home npx bin
  home=$(cb_home)
  npx="$home/.local/node/bin/npx"
  [[ -x $npx ]] || die "Node is missing, run the 'claude' step first"

  bin=$(find_playwright_chromium)
  if [[ -z $bin ]]; then
    log "installing Playwright Chromium $CB_PLAYWRIGHT_VERSION (and its system libraries)"
    # System libraries need root; the browser itself goes in the user's cache.
    DEBIAN_FRONTEND=noninteractive PATH="$home/.local/node/bin:$PATH" "$npx" -y "playwright@$CB_PLAYWRIGHT_VERSION" install-deps chromium >/dev/null
    local out
    # Without a package.json npx prints a harmless warning box; show output only on failure.
    out=$(as_user npx -y "playwright@$CB_PLAYWRIGHT_VERSION" install chromium 2>&1) || die "$out"
    bin=$(find_playwright_chromium)
    [[ -n $bin ]] || die "Playwright Chromium not found after install"
  fi
  ensure_chromium_apparmor
  echo "$bin"
}

find_playwright_chromium() {
  local home
  home=$(cb_home)
  find "$home/.cache/ms-playwright" -maxdepth 3 -type f -name chrome -path '*/chromium-*/*' 2>/dev/null | sort -V | tail -1
}

# Ubuntu 24.04 blocks unprivileged user namespaces unless an AppArmor profile
# allows them. Chrome's .deb ships one; Playwright's Chromium does not, and
# without it the sandbox fails. This grants userns to that binary only, so the
# browser keeps its sandbox (no --no-sandbox).
ensure_chromium_apparmor() {
  [[ -d /etc/apparmor.d ]] || return 0
  if ensure_file /etc/apparmor.d/claude-cloud-browser-chromium 644 root:root <<EOF; then
# Managed by claude-cloud-browser.
abi <abi/4.0>,
include <tunables/global>

profile claude-cloud-browser-chromium $(cb_home)/.cache/ms-playwright/chromium-*/chrome-linux*/chrome flags=(unconfined) {
  userns,
  include if exists <local/claude-cloud-browser-chromium>
}
EOF
    apparmor_parser -r /etc/apparmor.d/claude-cloud-browser-chromium
  fi
}

# Xvfb only accepts clients that hold this cookie, so other local users can
# neither watch nor type into the browser's display.
ensure_xauthority() {
  local home
  home=$(cb_home)
  if ! as_user xauth -f "$home/.Xauthority" list "$CB_DISPLAY" 2>/dev/null | grep . >/dev/null; then
    runuser -u "$CB_USER" -- touch "$home/.Xauthority"
    as_user xauth -q -f "$home/.Xauthority" add "$CB_DISPLAY" . "$(mcookie)"
    log "created X cookie for $CB_DISPLAY"
  fi
  chmod 600 "$home/.Xauthority"
}

# Cap everything the dedicated user runs (browser, Claude Code, its tools),
# so a runaway tab can never starve other services on the same server.
ensure_user_slice_limits() {
  if render "$CB_ROOT/systemd/system/user-slice.conf" |
    ensure_file "/etc/systemd/system/user-$(cb_uid).slice.d/50-claude-cloud-browser.conf" 644 root:root; then
    systemctl daemon-reload
  fi
}

wait_for_cdp() {

  for _ in $(seq 1 30); do
    if as_user curl -fsS "http://127.0.0.1:$CB_CDP_PORT/json/version" >/dev/null 2>&1; then
      ok "DevTools endpoint up on 127.0.0.1:$CB_CDP_PORT"
      return 0
    fi
    sleep 1
  done
  die "browser DevTools endpoint did not come up; check: cb logs chrome"
}
