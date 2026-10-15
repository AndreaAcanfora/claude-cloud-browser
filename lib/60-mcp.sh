# shellcheck shell=bash
# Playwright MCP, registered in Claude Code (user scope) and attached over
# CDP to THE always-on browser: Claude works in the same tabs, cookies and
# logins you see in noVNC, instead of spawning a fresh empty browser.

step_mcp() {
  local home npx endpoint pkg want have
  home=$(cb_home)
  npx="$home/.local/node/bin/npx"
  endpoint="http://127.0.0.1:$CB_CDP_PORT"
  pkg="@playwright/mcp@$CB_PLAYWRIGHT_MCP_VERSION"
  as_user bash -c 'command -v claude' >/dev/null || die "Claude Code is missing, run the 'claude' step first"

  # Download once now, so the first Claude session does not wait for npm.
  as_user npx -y "$pkg" --help >/dev/null

  want=$(jq -cn --arg c "$npx" --arg p "$pkg" --arg e "$endpoint" \
    '{command: $c, args: ["-y", $p, "--cdp-endpoint", $e]}')
  have=$(as_user bash -c 'cat ~/.claude.json 2>/dev/null' |
    jq -c '.mcpServers.playwright // {} | {command, args}' 2>/dev/null || true)

  if [[ $have == "$want" ]]; then
    ok "Playwright MCP already configured ($pkg -> $endpoint)"
    return 0
  fi
  as_user claude mcp remove --scope user playwright >/dev/null 2>&1 || true
  # -e takes several values, so it goes after the server name.
  as_user claude mcp add --scope user playwright \
    -e "PATH=$home/.local/node/bin:/usr/local/bin:/usr/bin:/bin" \
    -- "$npx" -y "$pkg" --cdp-endpoint "$endpoint" >/dev/null
  ok "Playwright MCP configured ($pkg -> $endpoint)"
}
