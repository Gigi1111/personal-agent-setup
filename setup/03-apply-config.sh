#!/usr/bin/env bash
# Run as the agent user after onboarding and after 05-save-telegram-token.sh.
# Applies the private gateway, Telegram and skill settings, adds the owner's
# rules, and runs a security audit.
# Usage: ./03-apply-config.sh 123456789   (your numeric Telegram user ID)
set -euo pipefail

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/openclaw-config.example.json5"
RULES="$SCRIPT_DIR/agent-rules.md"
RULES_MARKER="## Owner's rules"
TOKEN_FILE="$HOME/.openclaw/telegram-bot-token"

[[ $EUID -ne 0 ]] || die "Run as the agent user, not root."
[[ $# -eq 1 ]] || die "Usage: $0 123456789"
TELEGRAM_ID="$1"
[[ "$TELEGRAM_ID" =~ ^[1-9][0-9]{4,14}$ ]] \
  || die "Use your numeric Telegram user ID, not a username or phone number."
[[ "$TELEGRAM_ID" != "123456789" ]] || die "That's the placeholder ID. Use your real one."
[[ -f "$TEMPLATE" && -f "$RULES" ]] || die "Keep this script next to its template and rules files."
[[ -f "$TOKEN_FILE" && ! -L "$TOKEN_FILE" && -s "$TOKEN_FILE" ]] \
  || die "Bot token file missing. Run 05-save-telegram-token.sh first."
command -v openclaw >/dev/null || die "openclaw not found. Run: source ~/.profile"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
PATCH="$WORK_DIR/openclaw.patch.json5"
sed "s/\"123456789\"/\"$TELEGRAM_ID\"/" "$TEMPLATE" > "$PATCH"
[[ "$HOME" == "/home/agent" ]] || sed -i "s|/home/agent/|$HOME/|" "$PATCH"

echo "==> Checking the config change"
openclaw config patch --file "$PATCH" --dry-run

echo "==> Applying the config change"
openclaw config patch --file "$PATCH"
openclaw config validate

echo "==> Adding the owner's rules"
WORKSPACE="$(openclaw config get agents.defaults.workspace 2>/dev/null || true)"
WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
WORKSPACE="${WORKSPACE/#\~/$HOME}"
[[ -d "$WORKSPACE" ]] || die "Workspace $WORKSPACE not found. Run onboarding first."
if grep -qF "$RULES_MARKER" "$WORKSPACE/AGENTS.md" 2>/dev/null; then
  echo "Rules are already there."
else
  cat "$RULES" >> "$WORKSPACE/AGENTS.md"
fi

echo "==> Restricting OpenClaw's files to this user"
chmod 700 "$HOME/.openclaw"
chmod 600 "$TOKEN_FILE"

echo "==> Gateway login mode (the token itself isn't shown)"
openclaw config get gateway.auth.mode || echo "Not set. Check this before starting the gateway."

echo "==> Shell command approval policy"
openclaw approvals get || echo "Couldn't read the approval policy."

echo "==> Security audit"
openclaw security audit || echo "The audit reported problems. Review them before continuing."

echo
echo "Next: restart the gateway with 'openclaw gateway restart' if it's already running."
