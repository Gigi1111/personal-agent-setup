#!/usr/bin/env bash
# Run as the agent user. Asks for the Telegram bot token from @BotFather without
# showing it, and saves it to a file only this user can read. The token never
# appears on the command line, in shell history or in chat.
set -euo pipefail

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

TOKEN_FILE="$HOME/.openclaw/telegram-bot-token"

[[ $EUID -ne 0 ]] || die "Run as the agent user, not root."
[[ -d "$HOME/.openclaw" ]] || die "$HOME/.openclaw not found. Run onboarding first."

read -rsp "Paste the bot token from @BotFather, then press Enter (it won't be shown): " TOKEN
echo
TOKEN="$(printf '%s' "$TOKEN" | tr -d '[:space:]')"
[[ "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]] \
  || die "That doesn't look like a bot token (expected digits, a colon, then a long code)."

rm -f "$TOKEN_FILE"
( umask 077; printf '%s' "$TOKEN" > "$TOKEN_FILE" )
unset TOKEN
chmod 600 "$TOKEN_FILE"

echo "Saved. Only the agent user can read $TOKEN_FILE."
echo "Next: open your bot in Telegram, press Start or send it 'hi', then tell Claude it's done."
