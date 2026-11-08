# Instructions for coding agents

You're helping someone set up their own personal AI agent ([OpenClaw](https://www.npmjs.com/package/openclaw)) on a VPS they own, using the files in this repo. They talk to the agent through a private Telegram bot. Your job is to guide them through it safely, step by step. Running the scripts for them is fine when they ask.

## Read these first, in this order

1. `README.md`: the goal, what they need, and the setup steps in order. **It's your main source of truth.**
2. `setup/` scripts, numbered by when they were written, **not** by run order. The run order is **01 → 02 → onboarding → 05 → 03 → gateway service → 04**. Read each script before running it or asking the user to.
3. `setup/openclaw-config.example.json5`: the config template that `03-apply-config.sh` fills in.
4. `setup/agent-rules.md`: rules for the **deployed agent**, which script 03 appends to its `AGENTS.md` on the server. They aren't instructions for you. Help the user edit them if they want different rules.

Only if the user asks:
- `guide.md`: a separate, longer **team** setup (Hermes, Twenty CRM, Excalidraw, Tailscale). Don't mix it with the personal setup.
- `model-ranking.md`: notes on choosing a model.
- `setup/credits-left.sh`: an optional credit tracker. The README's "Make it yours" section explains how to install it.

## Before you start, find out

- Whether they already have a VPS running **Ubuntu 24.04 on x86-64**, with about 2 vCPU and 4 GB of RAM. The scripts stop on anything else.
- Whether they have an SSH key, and whether that key is on the server. Script 01 refuses to run without one, because it turns off password login.
- Whether they have an **OpenAI API key with a spending limit set at OpenAI**. OpenClaw has no spending cap of its own.
- The server's IP and the SSH username.

## Rules for you

- **Never ask the user to paste a secret into the chat.** That includes API keys, the Telegram bot token, and the contents of `~/.openclaw` or any token file. They type secrets into hidden prompts on the server themselves: `openclaw onboard` for the API key, and `05-save-telegram-token.sh` for the bot token. If they paste a secret anyway, tell them to revoke it and make a new one.
- **Never print a secret.** Don't `cat` token or credential files, run `env`, `curl -v`, or `docker compose config` without `--quiet`, or put a token in a command line. The README's Telegram ID command reads the token from its file for this reason.
- **Don't lock them out.** Before or after script 01, tell them to keep their current SSH session open until a login from a second terminal works.
- **Keep the security model.** Don't give the `agent` user sudo or Docker access, open firewall ports, expose the gateway beyond localhost, turn on Telegram groups, or install marketplace (ClawHub) skills, even to fix an error. If something seems to need one of these, stop and explain the trade-off.
- **Scripts 03, 04 and 05 haven't been run end to end yet** (see the README's status note). Run 03 with care, read its output, and stop at the first error instead of improvising around it.
- **The gateway service step isn't scripted.** Follow OpenClaw's current docs, and don't guess commands. Script 04 expects a systemd user service named `openclaw-gateway`.
- **Don't commit their details.** Their Telegram user ID, server IP, balances and config stay out of the repo. The template keeps the placeholder `123456789`.
- **Check before you say it's done.** Finish with `04-check-server.sh` (as root) and the tests in step 7 of the README.

## If you change the repo itself

- Keep the README's file table, run order and status note in sync with the scripts.
- Scripts are Bash with `set -euo pipefail`. Check every change with `bash -n` and, if you have it, `shellcheck`.
- Never add real secrets, IDs or personal notes. The `.gitignore` lists the patterns to keep out.
