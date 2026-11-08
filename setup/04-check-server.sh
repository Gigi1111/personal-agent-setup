#!/usr/bin/env bash
# Run as root. Read-only: reports whether the server is still locked down.
# Exits non-zero if any check fails.
set -uo pipefail

AGENT_USER="agent"
FAILURES=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
check() { # description, then the command to test
  local description="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$description"; else fail "$description"; fi
}

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 2; }

agent_has_no_admin_groups() { ! id -nG "$AGENT_USER" | tr ' ' '\n' | grep -qxE 'sudo|adm|docker|lxd'; }
agent_has_no_sudo_rules() { sudo -n -l -U "$AGENT_USER" 2>&1 | grep -q 'not allowed'; }
firewall_is_on() { ufw status | grep -q '^Status: active'; }
password_login_is_off() { sshd -T | grep -qx 'passwordauthentication no'; }
linger_is_on() { [[ "$(loginctl show-user "$AGENT_USER" --property=Linger --value)" == "yes" ]]; }
gateway_is_running() { systemctl --user -M "$AGENT_USER@" is-active --quiet openclaw-gateway.service; }
gateway_starts_on_boot() { systemctl --user -M "$AGENT_USER@" is-enabled --quiet openclaw-gateway.service; }
home_is_private() { [[ "$(stat -c '%a' "/home/$AGENT_USER")" == "700" ]]; }
openclaw_dir_is_private() { [[ "$(stat -c '%a' "/home/$AGENT_USER/.openclaw")" == "700" ]]; }
bot_token_is_private() { [[ "$(stat -c '%a' "/home/$AGENT_USER/.openclaw/telegram-bot-token")" == "600" ]]; }

check "Agent user exists" id "$AGENT_USER"
check "Agent user isn't in an admin group" agent_has_no_admin_groups
check "Agent user has no sudo rules" agent_has_no_sudo_rules
check "Agent's home directory is private" home_is_private
check "OpenClaw's directory is private" openclaw_dir_is_private
check "Telegram bot token is private" bot_token_is_private
check "Firewall is on" firewall_is_on
check "SSH password login is off" password_login_is_off
check "Agent services can run after logout and reboot" linger_is_on
check "Gateway is running" gateway_is_running
check "Gateway starts on boot" gateway_starts_on_boot

# Only SSH may listen beyond this machine.
SSH_PORT="$(sshd -T | awk '$1 == "port" && !found { print $2; found = 1 }')"
EXPOSED=0
while read -r address; do
  [[ -n "$address" ]] || continue
  host="${address%:*}"
  port="${address##*:}"
  case "$host" in
    127.*|'[::1]') continue ;;
  esac
  if [[ "$port" != "$SSH_PORT" ]]; then
    fail "Port exposed beyond this machine: $address"
    EXPOSED=1
  fi
done < <(ss -H -tln | awk '{ print $4 }')
[[ $EXPOSED -eq 1 ]] || pass "Only SSH listens beyond this machine"

echo
if [[ $FAILURES -eq 0 ]]; then
  echo "All checks passed."
else
  echo "$FAILURES check(s) failed."
  exit 1
fi
