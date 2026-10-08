#!/usr/bin/env bash
# Create the preferred RGB-Pi 27 maintenance account.
# Existing RGB-Pi system users are deliberately left untouched for compatibility.

set -euo pipefail

ADMIN_USER="${RGBPI_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${RGBPI_ADMIN_PASSWORD:-admin}"
SUDOERS_FILE="/etc/sudoers.d/020_rgbpi-updater27-admin"
RESET_PASSWORD="NO"

case "${1:-}" in
  --reset-password) RESET_PASSWORD="YES" ;;
  "") ;;
  *) echo "Usage: sudo bash $0 [--reset-password]"; exit 1 ;;
esac

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Root privileges are required."
  exit 77
fi

if [[ ! "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Invalid admin username: $ADMIN_USER"
  exit 2
fi

created="NO"
if ! id "$ADMIN_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$ADMIN_USER"
  created="YES"
fi

if [[ "$created" == "YES" || "$RESET_PASSWORD" == "YES" ]]; then
  printf '%s:%s\n' "$ADMIN_USER" "$ADMIN_PASSWORD" | chpasswd
fi

# Give the maintenance account the hardware-access groups that exist on the
# target OS, without assuming every Raspberry Pi group is present.
for group in sudo audio video input render plugdev netdev dialout gpio spi i2c bluetooth; do
  if getent group "$group" >/dev/null 2>&1; then
    usermod -aG "$group" "$ADMIN_USER"
  fi
done

tmp="$(mktemp)"
printf '%s ALL=(ALL:ALL) ALL\n' "$ADMIN_USER" > "$tmp"
chmod 0440 "$tmp"

if command -v visudo >/dev/null 2>&1; then
  visudo -cf "$tmp" >/dev/null
fi

install -o root -g root -m 0440 "$tmp" "$SUDOERS_FILE"
rm -f "$tmp"

echo
echo "RGB-Pi 27 maintenance account ready."
echo "User: $ADMIN_USER"
if [[ "$created" == "YES" || "$RESET_PASSWORD" == "YES" ]]; then
  echo "Initial password: $ADMIN_PASSWORD"
  echo
  echo "IMPORTANT: Change the default password after the first login:"
  echo "  passwd"
else
  echo "Existing password was not changed."
fi
echo
echo "The original RGB-Pi account was not renamed or removed."
echo "That is intentional so OS4 services and scripts that still reference it keep working."
