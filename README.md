# Personal AI agent on a locked-down VPS

Scripts and a guide for running your own always-on AI agent ([OpenClaw](https://www.npmjs.com/package/openclaw)) on a small Ubuntu server. You talk to it through a private Telegram bot, and it pays per use from OpenAI API credits.

The setup puts security before convenience:

- The agent runs as its own user, with **no sudo and no Docker access**.
- **SSH key login only**, with a firewall and automatic security updates.
- The gateway listens on **localhost only**. Telegram uses outbound long polling, so **no inbound port** is opened for the bot.
- The bot answers **direct messages from your numeric Telegram user ID only**. Groups are off.
- **Secrets never go into files in this repo or into a chat.** You type the bot token and API key into hidden prompts on the server.
- **No marketplace skills.** The agent gets a set of [owner's rules](setup/agent-rules.md) covering approvals, secrets and spending.

> **Status:** scripts 01 and 02 have been run on a real server. Scripts 03, 04 and 05 have been syntax-checked and dry-run, but not yet run end to end. Read every script before you run it, and report anything that breaks.

## What you need

- A VPS running **Ubuntu 24.04 on x86-64**, with about 2 vCPU and 4 GB of RAM. Monthly billing is fine while you're testing.
- An **SSH key** on your computer, added to the server when you create it.
- An **OpenAI API key** with a **spending limit set in OpenAI's dashboard**. OpenClaw has no spending cap of its own.
- A **Telegram account**.

## Files

| File | Run as | What it does |
|---|---|---|
| [`setup/01-server-bootstrap.sh`](setup/01-server-bootstrap.sh) | root | Updates packages, creates the `agent` user, turns on automatic updates and the firewall, and turns off SSH password login |
| [`setup/02-install-openclaw.sh`](setup/02-install-openclaw.sh) | `agent` | Installs Node 24 in the user's home after checking its checksum, then installs OpenClaw from npm |
| [`setup/05-save-telegram-token.sh`](setup/05-save-telegram-token.sh) | `agent` | Asks for the bot token without showing it, then saves it to a file only the agent user can read |
| [`setup/03-apply-config.sh`](setup/03-apply-config.sh) | `agent` | Applies the config with your Telegram ID, adds the owner's rules, locks down file permissions and runs OpenClaw's security audit |
| [`setup/04-check-server.sh`](setup/04-check-server.sh) | root | Read-only check that the server is still locked down |
| [`setup/credits-left.sh`](setup/credits-left.sh) | `agent` | Optional. Estimates the credit left from your last billing-page balance minus OpenClaw's tracked spend |
| [`setup/openclaw-config.example.json5`](setup/openclaw-config.example.json5) | used by 03 | The config template. Don't put secrets in it |
| [`setup/agent-rules.md`](setup/agent-rules.md) | used by 03 | Rules appended to the agent's `AGENTS.md` |
| [`guide.md`](guide.md) | | A separate, longer guide to a **team** setup with Hermes, Twenty CRM, Excalidraw and Tailscale |
| [`model-ranking.md`](model-ranking.md) | | Notes on choosing a model for cost and speed |
| [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md) | | Instructions for a coding agent (Codex, Claude Code and others) helping you set this up |

**Run 05 before 03.** Script 03 stops if the token file is missing.

## Setup

**Using a coding agent?** Open this folder in Codex, Claude Code or a similar tool and ask it to help you set up your personal agent. It will read `AGENTS.md` (Claude Code reads `CLAUDE.md`, which points to the same file) to learn which files to use and which safety rules to follow.

### 1. Lock down the server (as root)

Copy the `setup/` folder to the server, for example with `scp -r setup root@YOUR_SERVER_IP:`. Then run:

```bash
bash setup/01-server-bootstrap.sh
```

**Keep this SSH session open** until a new login works from a second terminal. The script turns off password login.

Then give the agent user its own copy of the scripts:

```bash
cp -r setup /home/agent/ && chown -R agent:agent /home/agent/setup
sudo -iu agent
```

### 2. Install OpenClaw and connect the model (as `agent`)

```bash
bash ~/setup/02-install-openclaw.sh
source ~/.profile
openclaw onboard --auth-choice openai-api-key
```

Type the API key into the onboarding prompt yourself. Don't paste it into any chat, including one with an AI assistant.

### 3. Create the Telegram bot

1. In Telegram, message **@BotFather**, send `/newbot`, and follow the steps.
2. Send `/setjoingroups`, pick your bot and choose **Disable**, so nobody can add it to a group.
3. On the server, as `agent`, run `bash ~/setup/05-save-telegram-token.sh` and paste the token when it asks.

### 4. Find your numeric Telegram user ID

Open your bot in Telegram and press **Start**. Then, on the server, **before any gateway is running**:

```bash
printf 'url = "https://api.telegram.org/bot%s/getUpdates"\n' "$(cat ~/.openclaw/telegram-bot-token)" \
  | curl -s -K - | jq '.result[].message.from.id'
```

This reads the token from a file, so it never appears in your shell history or the process list. Use the numeric ID, not your username. Usernames can change or be taken over.

### 5. Apply the config and rules (as `agent`)

```bash
bash ~/setup/03-apply-config.sh YOUR_NUMERIC_ID
```

Read the security audit at the end before you continue.

### 6. Run the gateway as a service

This step isn't scripted yet. Install and start the OpenClaw gateway as a **systemd user service** named `openclaw-gateway` by following OpenClaw's docs. Script 01 already turned on lingering, so the service keeps running after you log out and after a reboot. Only one process may poll a bot at a time, so never run two gateways on the same token.

### 7. Check everything (as root)

```bash
bash /home/agent/setup/04-check-server.sh
```

Then test it:
- Your account gets replies. Other accounts and groups get nothing.
- `sudo` and `docker` fail for the agent.
- A hidden instruction inside a pasted email or web page is treated as text, not obeyed.
- The bot still replies after a reboot.

## Make it yours

- **Model:** the template uses `openai/gpt-6.1-terra` by default, and the rules ask before switching to a bigger model. Check OpenAI's current prices and change both files to match the models you want.
- **Background jobs cost money.** OpenClaw can run a periodic heartbeat (`openclaw system heartbeat disable`) and a nightly memory job (`/dreaming off`). Turn off whatever you don't need.
- **Shell commands:** by default the agent runs commands without asking. Look at `openclaw exec-policy preset cautious` before you give it any real accounts.
- **Credit tracker (optional):** install it with `sudo install -m 755 setup/credits-left.sh /usr/local/bin/credits-left`. Then record your balance, as `agent`, with `credits-left --set 25.00 2026-01-15 2026-12-31`. The last date is when the credit expires, and you can leave it out.
- **Rules:** edit `setup/agent-rules.md` before you run 03. Rules guide the agent, but they don't enforce anything. The real limits are the locked-down user and narrowly scoped keys.

## Things to know

- **Telegram bot chats aren't end-to-end encrypted.** Telegram can read what you send the bot.
- **If the bot token leaks,** revoke it in @BotFather, save the new one with script 05, then restart the gateway.
- **Give the agent narrow keys.** For example, use a GitHub token limited to one test repo, and have the agent work through pull requests, never by pushing to `main`.
- **Back up** `~/.openclaw` (config and workspace), and keep the backup encrypted, because it holds credentials.
