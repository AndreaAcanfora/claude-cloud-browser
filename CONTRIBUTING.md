# Contributing

Thanks for helping! A few rules keep the installer safe to re-run on real servers.

## Ground rules

- **Idempotent or nothing.** Every step must be safe to run again. Use the helpers in `lib/common.sh`
  (`ensure_file`, `ensure_line`, `apt_install`, `install_user_unit`) instead of blind writes.
- **Never handle credentials.** No step may ask for, store or transmit a password, token or API key.
- **Never remove what you did not create.** Especially firewall rules and SSH settings: the installer also runs on servers that host other services.
- **Bind to 127.0.0.1.** New local services must not listen on public interfaces, and must be added to the port guard.
- **Messages to stderr.** `log`/`ok`/`warn` print to stderr so `$(...)` captures only data.

## Workflow

1. Fork and create a branch.
2. Run `shellcheck -x install.sh lib/*.sh bin/cb bin/cb-rc-ready` (CI runs the same).
3. Test on a throwaway Ubuntu 24.04 server: run `install.sh` twice, the second run must change nothing, then `cb status`.
4. Open a pull request describing what you changed and how you tested it (architecture, provider).

## Adding a step

Create `lib/NN-name.sh` with a `step_name` function and add `name` to `STEPS` in `install.sh`.
Keep the number prefix in execution order.

## Reporting security issues

Use GitHub's private vulnerability reporting, not a public issue.
