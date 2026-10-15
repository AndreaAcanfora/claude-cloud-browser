# shellcheck shell=bash
# Node LTS for the dedicated user only (the system Node, if any, is never
# touched) and the official Claude Code CLI from npm.
#
# No credentials here: you log in yourself by running `claude` once.

step_claude() {
  ensure_node
  ensure_shell_path

  if as_user bash -c 'command -v claude' >/dev/null; then
    ok "Claude Code already installed ($(as_user claude --version 2>/dev/null | head -1)); it updates itself"
  else
    log "installing Claude Code"
    as_user npm install -g --silent @anthropic-ai/claude-code
    ok "Claude Code $(as_user claude --version | head -1)"
  fi
}

node_arch() {
  case $(detect_arch) in
    amd64) echo x64 ;;
    arm64) echo arm64 ;;
    *) die "unsupported architecture: $(detect_arch)" ;;
  esac
}

ensure_node() {
  local home version arch dir tmp
  home=$(cb_home)
  arch=$(node_arch)
  if [[ $CB_NODE_VERSION == lts ]]; then
    # The first LTS entry is the newest LTS release.
    version=$(curl -fsSL https://nodejs.org/dist/index.json | jq -r '[.[] | select(.lts != false)][0].version')
  else
    version=v${CB_NODE_VERSION#v}
  fi
  [[ $version == v* ]] || die "could not resolve the Node version"

  dir="$home/.local/node-$version"
  if [[ ! -x $dir/bin/node ]]; then
    log "installing Node $version ($arch) in $dir"
    tmp=$(mktemp -d)
    local tarball="node-$version-linux-$arch.tar.xz"
    curl -fsSL -o "$tmp/$tarball" "https://nodejs.org/dist/$version/$tarball"
    curl -fsSL -o "$tmp/SHASUMS256.txt" "https://nodejs.org/dist/$version/SHASUMS256.txt"
    (cd "$tmp" && grep " $tarball\$" SHASUMS256.txt | sha256sum -c --quiet) || die "Node checksum mismatch"
    runuser -u "$CB_USER" -- mkdir -p "$dir"
    tar -xJf "$tmp/$tarball" -C "$dir" --strip-components=1
    chown -R "$CB_USER:$CB_USER" "$dir"
    rm -rf "$tmp"
  fi
  # Stable path used by PATH, units and the MCP config.
  if [[ $(readlink "$home/.local/node" 2>/dev/null) != "$dir" ]]; then
    runuser -u "$CB_USER" -- ln -sfn "$dir" "$home/.local/node"
    log "Node $version is now the active version"
  fi
  # Global packages live outside the Node directory, so they survive Node upgrades.
  as_user npm config set prefix "$home/.local/npm" >/dev/null
  ok "Node $(as_user node --version) for $CB_USER"
}

ensure_shell_path() {
  local home line
  home=$(cb_home)
  # shellcheck disable=SC2016
  line='export PATH="$HOME/.local/bin:$HOME/.local/npm/bin:$HOME/.local/node/bin:$PATH"'
  ensure_line "$home/.profile" "$line"
  ensure_line "$home/.bashrc" "$line"
  chown "$CB_USER:$CB_USER" "$home/.profile" "$home/.bashrc"
}
