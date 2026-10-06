#!/bin/sh
# One-time setup inside the macOS VM, run from the guest's Terminal:
#
#   sh "/Volumes/My Shared Files/<share>/showreel/guest/bootstrap.sh"
#
# Lets the host drive the guest over SSH: authorizes the key written by
# `scripts/showreel vm setup`, turns on Remote Login, keeps the session awake
# and unlocked, and records the guest's user and MAC address so the host can
# find its IP address in /var/db/dhcpd_leases.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
state="$here/../.vm"
pub="$state/host_key.pub"

if [ ! -f "$pub" ]; then
    echo "✗ $pub is missing — run 'scripts/showreel vm setup' on the host first" >&2
    exit 1
fi

echo "→ Authorizing the host's key"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
if ! grep -qxF "$(cat "$pub")" "$HOME/.ssh/authorized_keys"; then
    cat "$pub" >>"$HOME/.ssh/authorized_keys"
fi
chmod 600 "$HOME/.ssh/authorized_keys"

echo "→ Turning on Remote Login (sudo asks for this Mac's password)"
if ! nc -z -G 2 127.0.0.1 22 2>/dev/null; then
    sudo launchctl enable system/com.openssh.sshd
    sudo launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
    sleep 1
fi
if nc -z -G 2 127.0.0.1 22 2>/dev/null; then
    echo "  ✓ sshd is listening"
else
    echo "  ✗ sshd is not listening — turn on System Settings › General › Sharing › Remote Login" >&2
fi

echo "→ Keeping the session awake and unlocked"
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
defaults -currentHost write com.apple.screensaver idleTime -int 0

echo "→ Recording the guest's identity for the host"
iface="$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')"
mac="$(ifconfig "${iface:-en0}" 2>/dev/null | awk '/ether / { print $2 }')"
{
    echo "GUEST_USER=$(id -un)"
    echo "GUEST_MAC=$mac"
    echo "GUEST_HOSTNAME=$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
    echo "GUEST_MACOS=$(sw_vers -productVersion)"
} >"$state/guest.env"
cat "$state/guest.env"

echo "✓ Done. Back on the host, run: scripts/showreel vm doctor"
