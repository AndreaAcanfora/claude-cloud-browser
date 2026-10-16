# Getting started, step by step

This guide takes you from nothing to "I ask Claude something on my phone and it does it in my own browser in the cloud".
It assumes no Linux experience. Everything can be done from a phone; a computer works the same way.

**Time:** about 30 minutes. **Cost:** a few euros per month for the server, plus your own Claude plan.

## Contents

1. [What you need](#1-what-you-need)
2. [Create an SSH key in Termius](#2-create-an-ssh-key-in-termius)
3. [Create the server](#3-create-the-server)
4. [Check that the installation finished](#4-check-that-the-installation-finished)
5. [Connect the server to Tailscale](#5-connect-the-server-to-tailscale)
6. [Log in to Claude](#6-log-in-to-claude)
7. [Open the browser from your phone and log in to your sites](#7-open-the-browser-from-your-phone-and-log-in-to-your-sites)
8. [Optional: use Claude from the Claude app (Remote Control)](#8-optional-use-claude-from-the-claude-app-remote-control)
9. [Everyday use](#9-everyday-use)
10. [Troubleshooting](#10-troubleshooting)
11. [Installing on a server you already have](#11-installing-on-a-server-you-already-have)

---

## 1. What you need

| What | Why | Where |
|---|---|---|
| A **Claude subscription** (Pro or Max) | Claude Code logs in with your own account | [claude.ai](https://claude.ai) |
| A **Hetzner Cloud** account (or any provider with Ubuntu 24.04) | The server that runs Claude and the browser | [hetzner.com/cloud](https://www.hetzner.com/cloud) |
| A **Tailscale** account (free plan is enough) | A private network between your phone and the server, so the browser screen is never on the internet | [tailscale.com](https://tailscale.com) |
| **Termius** on your phone (free) | SSH terminal to talk to the server | App Store / Google Play |
| The **Tailscale** app on your phone | Joins your phone to the private network | App Store / Google Play |

Log in to the Tailscale app on your phone now, with the account you will also use for the server.

## 2. Create an SSH key in Termius

An SSH key is how the server recognises you. There are no passwords: password login is switched off by the installer.

1. Open Termius → **Keychain** (or **Vault → Keychain**) → **+** → **Generate Key**.
2. Type: **ED25519**. Name: anything, for example `phone`. Save.
3. Open the key and copy the **public key**: a single line that starts with `ssh-ed25519 AAAA...`.
   The public key is safe to share. The private key never leaves your phone.

## 3. Create the server

In the [Hetzner Cloud console](https://console.hetzner.cloud): open (or create) a project → **Add Server**.

1. **Location:** any.
2. **Image:** **Ubuntu 24.04**.
3. **Type:** shared vCPU, **Arm64 (Ampere)**, **CAX21** (4 vCPU, 8 GB) recommended. CAX11 (2 vCPU, 4 GB) works for light use.
   x86 types work too.
4. **SSH keys:** **Add SSH key**, paste the public key from step 2, select it.
   This key lets you log in as `root` for maintenance.
5. **Cloud config** (sometimes called "user data"): paste the text below, replacing the key line with **your public key from step 2**:

   ```yaml
   #cloud-config
   write_files:
     - path: /etc/claude-cloud-browser/install.env
       permissions: "0644"
       content: |
         CB_SSH_PUBKEY='ssh-ed25519 AAAA...your-key...'
         CB_TS_HOSTNAME=claude-vps

   runcmd:
     - [bash, -c, "apt-get update -qq && apt-get install -y -qq git"]
     - [git, clone, --depth, "1", https://github.com/AndreaAcanfora/claude-cloud-browser, /opt/claude-cloud-browser]
     - [bash, /opt/claude-cloud-browser/install.sh]
   ```

   The same file is in [cloud-init/user-data.yaml](../cloud-init/user-data.yaml).
6. **Name:** anything. **Create & Buy now**. Note the server's **IPv4** address.

The server boots and installs everything by itself. It takes **5 to 10 minutes**.

## 4. Check that the installation finished

Add two hosts in Termius (**Hosts → + → New Host**), both with the key from step 2 in the **Key** field and the password empty:

| Alias | Hostname | Username | Use it for |
|---|---|---|---|
| `my-server root` | the server IPv4 | `root` | maintenance (steps 4 and 5) |
| `my-server claude` | the server IPv4 | `claude` | everyday use with Claude |

The first time you connect, Termius shows the server fingerprint: tap **Continue**.

Connect as **root** and run:

```bash
cloud-init status --wait     # waits until the installer is done
tail -n 30 /var/log/cloud-init-output.log
```

The end of the log should say `done. Run 'cb status' to check the services.`
If it shows an `ERROR`, see [Troubleshooting](#10-troubleshooting).

## 5. Connect the server to Tailscale

Still connected as **root**:

1. Join your tailnet:

   ```bash
   tailscale up --hostname=claude-vps
   ```

   It prints a link `https://login.tailscale.com/a/...`. Long-press it, open it, log in with the **same Tailscale account as your phone** and approve.
2. Publish the browser screen (noVNC) on your tailnet:

   ```bash
   bash /opt/claude-cloud-browser/install.sh --only tailscale
   ```

   On a brand new tailnet Tailscale asks you to **enable HTTPS / Serve** once: the command prints a link
   `https://login.tailscale.com/f/serve?...`. Open it, enable, then run the same command again.
   It should end with `noVNC published on the tailnet`.
3. Recommended: in the [Tailscale admin console](https://login.tailscale.com/admin/machines), open `claude-vps` → **⋯** → **Disable key expiry**.
   Otherwise the server leaves your tailnet after a few months.

## 6. Log in to Claude

Connect with the **claude** host in Termius. You land in a `tmux` session (a green bar at the bottom): it keeps your work alive
when the phone disconnects. Then:

1. Type `claude` and press Enter.
2. Pick a theme, then **Claude account with subscription**. Use the arrow keys in the bar above the Termius keyboard, then Enter.
3. Claude prints a long link `https://claude.ai/oauth/...`. Long-press it, copy, open it in your phone browser.
4. Log in to Claude and tap **Authorize**. The page shows a **code**: copy it.
5. Back in Termius, paste the code (long-press → Paste) and press Enter.
6. If it asks whether you trust the folder, answer yes.

Check that Claude sees the browser: type `/mcp`. **playwright** should be listed as connected.
Then try: `Open example.com and tell me the page title.`

## 7. Open the browser from your phone and log in to your sites

1. In the Termius **claude** session, open a new tmux window with `Ctrl-b` then `c` (Ctrl is in the bar above the keyboard), and run:

   ```bash
   cb browser
   ```

   It prints an address like `https://claude-vps.<your-tailnet>.ts.net/vnc.html?...` (with `:8443` after `.ts.net`
   if the server also runs a website) and the **VNC password**.
   Go back to Claude's window with `Ctrl-b` then `p`.
2. Make sure the **Tailscale app is on**, then open that address in your phone browser and enter the VNC password.
3. You see the server's Chrome. Log in to the websites you want Claude to use. Your logins are saved in the browser profile on the server.

You can come back here whenever a site asks for a captcha or a 2FA code. Pinch to zoom; the noVNC side menu has a keyboard button.

> [!IMPORTANT]
> Claude can act on every site you are logged in to in that browser. Log in only where you want it to work,
> prefer accounts with limited permissions, and keep an eye on what it does.

## 8. Optional: use Claude from the Claude app (Remote Control)

Instead of the terminal, you can talk to the Claude on your server from the **Claude app** (Code section) or from
[claude.ai/code](https://claude.ai/code), with the same browser and tools. The installer sets this up as an
**always-on service** (`cb-remote-control`): it restarts by itself and survives reboots, so after this step you
don't need Termius for everyday use.

The service needs two things that only you can do, once:

1. **You are logged in to Claude** (step 6).
2. **You trust the workspace folder.** Claude Code refuses to run Remote Control in a home directory, so the installer
   created `~/workspace` (with a `CLAUDE.md` that tells Claude about the browser). In Termius, as `claude`:

   ```bash
   cd ~/workspace
   claude
   ```

   Claude asks whether you trust this folder. The highlighted answer is **No, exit**: press the down arrow to
   **Yes, I trust this folder**, then Enter. If it then offers other options (for example a new renderer), pick what you like.
   Then type `/exit`.
3. Start the service:

   ```bash
   cb restart remote
   cb status        # cb-remote-control should be "active"
   ```

4. In the Claude app, open **Code**: a session named `claude-vps` (your `CB_TS_HOSTNAME`) appears. Open it and chat.

Every tool use asks for your approval in the app by default. To change that, set `CB_RC_PERMISSION_MODE`
(for example `acceptEdits`) and re-run `install.sh --only remote`. If the service restarts, a new session appears in the app.

## 9. Everyday use

| You want to | Do this |
|---|---|
| Talk to Claude from the terminal | Termius → **claude** host. You are back in the same tmux session, Claude included |
| Talk to Claude from the Claude app | Open the `claude-vps` session in the app's Code section (step 8) |
| See or use the browser | `cb browser`, open the address with Tailscale on |
| Check that everything runs | `cb status` |
| Restart the browser | `cb restart chrome` (or `cb restart` for everything) |
| Restart Remote Control | `cb restart remote` |
| Read logs | `cb logs chrome`, `cb logs -f` to follow |
| Leave Claude running and close Termius | `Ctrl-b` then `d` |
| New terminal window next to Claude | `Ctrl-b` then `c`; switch with `Ctrl-b` then `n` / `p` |
| Turn off tmux auto-attach | `touch ~/.no-tmux` (remove the file to turn it back on) |

**Updating.** Claude Code updates itself. For the rest, as root:

```bash
cd /opt/claude-cloud-browser && git pull && bash install.sh
```

The installer is safe to re-run: it only changes what is out of date.

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| Termius asks for a password | The **Key** field of the host is empty or holds another key. Pick the key from step 2 |
| `Permission denied (publickey)` as `claude` | The key in `CB_SSH_PUBKEY` is not the Termius one. As root: `CB_SSH_PUBKEY='ssh-ed25519 ...' bash /opt/claude-cloud-browser/install.sh --only ssh` |
| `cloud-init status` says `error` | Read `/var/log/cloud-init-output.log`, then re-run `bash /opt/claude-cloud-browser/install.sh` as root |
| `cb browser` says Tailscale is not connected | Do step 5 |
| The noVNC address does not open | The Tailscale app on the phone must be on and logged in to the same account as the server |
| noVNC shows a black screen | Wait a few seconds; if it stays black, `cb restart` |
| `cb status` shows a service not active | `cb logs <name>` to see why, then `cb restart <name>` |
| `cb-remote-control` is inactive | You are not logged in to Claude or did not trust `~/workspace`: see step 8. Details: `cb logs remote` |
| Claude does not list **playwright** in `/mcp` | As root: `bash /opt/claude-cloud-browser/install.sh --only browser,mcp` |
| A website on the same server (Caddy, nginx) does not start after a reboot | Old installs served noVNC on port 443. Update and re-run the installer as root (step 9): it moves noVNC to port 8443 |
| A site logs you out or shows a captcha | Open the browser with `cb browser` and solve it by hand, then ask Claude to continue |

Still stuck? [Open an issue](https://github.com/AndreaAcanfora/claude-cloud-browser/issues) with the output of `cb status`.

## 11. Installing on a server you already have

Any Ubuntu 24.04 server works, also one that already runs other services:

```bash
# as root
git clone https://github.com/AndreaAcanfora/claude-cloud-browser /opt/claude-cloud-browser
CB_SSH_PUBKEY='ssh-ed25519 AAAA...your-key...' bash /opt/claude-cloud-browser/install.sh
```

Then continue from [step 5](#5-connect-the-server-to-tailscale).

On a server with an active firewall, the installer only **adds** the SSH rule and never removes existing ones.
Everything runs as a separate user with a memory and CPU cap, and the browser's local ports are reserved to that user.

**Before you run it**, make sure `root` can log in with an SSH key (not only a password): the installer switches password
login off once both `root` and the `claude` user have a key. Set `CB_HARDEN_SSH=no` to leave SSH settings untouched.
