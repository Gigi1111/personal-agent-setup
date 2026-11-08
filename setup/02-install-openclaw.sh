#!/usr/bin/env bash
# Run as the agent user, not root. Installs Node 24 in the user's home directory
# (no admin rights needed) after verifying its checksum, then installs OpenClaw
# from npm. It does not start onboarding or handle any API keys.
set -euo pipefail

MIN_NODE="24.22.1" # OpenClaw's docs strongly recommend this or newer on Node 24.
NODE_BASE="https://nodejs.org/dist/latest-v24.x"
NODE_DIR="$HOME/.local/node"

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
version_at_least() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

[[ $EUID -ne 0 ]] || die "Run as the agent user, not root."
if sudo -n true 2>/dev/null; then
  die "This user has passwordless sudo. The agent user must not have admin rights."
fi
if id -nG | tr ' ' '\n' | grep -qxE 'sudo|docker'; then
  die "This user is in the sudo or docker group. Remove it before continuing."
fi
[[ "$(uname -m)" == "x86_64" ]] || die "This script expects an x86-64 server."

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Downloading Node 24"
curl -fsSL "$NODE_BASE/SHASUMS256.txt" -o "$WORK_DIR/SHASUMS256.txt"
NODE_FILE="$(awk '$2 ~ /^node-v[0-9.]+-linux-x64\.tar\.xz$/ { print $2; exit }' "$WORK_DIR/SHASUMS256.txt")"
[[ -n "$NODE_FILE" ]] || die "Could not find the Node download in the checksum list."
curl -fsSL "$NODE_BASE/$NODE_FILE" -o "$WORK_DIR/$NODE_FILE"

echo "==> Verifying checksum"
(cd "$WORK_DIR" && grep -F "  $NODE_FILE" SHASUMS256.txt | sha256sum -c -)

echo "==> Installing Node to $NODE_DIR"
rm -rf "$NODE_DIR"
mkdir -p "$NODE_DIR"
tar -xJf "$WORK_DIR/$NODE_FILE" --strip-components=1 -C "$NODE_DIR"
export PATH="$NODE_DIR/bin:$PATH"

NODE_VERSION="$(node --version)"
NODE_VERSION="${NODE_VERSION#v}"
version_at_least "$NODE_VERSION" "$MIN_NODE" \
  || die "Node $NODE_VERSION is older than the recommended $MIN_NODE."

# Add Node to PATH and make the systemd user bus reachable in future logins.
PROFILE_MARKER="# openclaw-setup"
if ! grep -qF "$PROFILE_MARKER" "$HOME/.profile" 2>/dev/null; then
  cat >> "$HOME/.profile" <<EOF

$PROFILE_MARKER
export PATH="\$HOME/.local/node/bin:\$PATH"
export XDG_RUNTIME_DIR="/run/user/\$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=\$XDG_RUNTIME_DIR/bus"
EOF
fi

echo "==> Installing OpenClaw"
# OpenClaw's docs say to leave out --allow-scripts on npm 11.15 and earlier.
NPM_VERSION="$(npm --version)"
if version_at_least "$NPM_VERSION" "11.16.0"; then
  npm install -g openclaw@latest --allow-scripts=openclaw
else
  npm install -g openclaw@latest
fi

echo
echo "Node:     $(node --version)"
echo "npm:      $(npm --version)"
echo "OpenClaw: $(openclaw --version)"
echo
echo "Next: run 'source ~/.profile', then 'openclaw onboard --auth-choice openai-api-key'"
echo "Enter the API key at the prompt yourself. Don't paste it into a chat."
