#!/usr/bin/env bash
# Run once as root (or with sudo) on a fresh Ubuntu 24.04 VPS.
# Updates packages, creates a locked-down agent user, enables automatic
# security updates and a firewall, and turns off SSH password login.
# Keep your current SSH session open until a new login has been confirmed.
set -euo pipefail

AGENT_USER="agent"

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root or with sudo."

# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] \
  || die "Expected Ubuntu 24.04, found ${PRETTY_NAME:-unknown}."

# Password login is turned off below, so make sure a key login exists first.
ADMIN_USER="${SUDO_USER:-root}"
ADMIN_HOME="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
[[ -s "$ADMIN_HOME/.ssh/authorized_keys" ]] \
  || die "No SSH key found for $ADMIN_USER. Add one first to avoid a lockout."

echo "==> Updating packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
apt-get install -y ca-certificates curl git jq openssl ufw unattended-upgrades xz-utils

echo "==> Creating agent user: $AGENT_USER"
if ! id "$AGENT_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos '' "$AGENT_USER"
fi
chmod 700 "/home/$AGENT_USER"
for group in sudo adm docker lxd; do
  if id -nG "$AGENT_USER" | tr ' ' '\n' | grep -qx "$group"; then
    die "$AGENT_USER is in the $group group. Remove it before continuing."
  fi
done
# Lets the agent's systemd user service keep running after logout and reboot.
loginctl enable-linger "$AGENT_USER"

echo "==> Enabling automatic security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "==> Turning off SSH password login"
# The first value sshd reads wins, so this file sorts before cloud-init's.
SSH_DROPIN="/etc/ssh/sshd_config.d/00-agent-hardening.conf"
cat > "$SSH_DROPIN" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
if ! sshd -t; then
  rm -f "$SSH_DROPIN"
  die "SSH config test failed. Change reverted."
fi
systemctl reload ssh

echo "==> Enabling firewall"
# awk must read all of its input: exiting early kills sshd with SIGPIPE, which
# pipefail and set -e turn into a script failure.
SSH_PORT="$(sshd -T | awk '$1 == "port" && !found { print $2; found = 1 }')"
[[ -n "$SSH_PORT" ]] || die "Could not detect the SSH port."
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp"
ufw --force enable

echo
echo "Done. Before closing this session, confirm a new SSH login works."
echo "Next: sudo -iu $AGENT_USER, then run 02-install-openclaw.sh"
