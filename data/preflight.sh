#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="${DATA_ROOT:-$SCRIPT_DIR}"
APP_ROOT="${APP_ROOT:-$(cd -- "${DATA_ROOT}/.." && pwd)}"

ARCH="$(uname -m 2>/dev/null || echo unknown)"
KERNEL="$(uname -r 2>/dev/null || echo unknown)"
MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo unknown)"
OS_ID="unknown"
OS_CODENAME="unknown"
OS_PRETTY="unknown"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_CODENAME="${VERSION_CODENAME:-unknown}"
  OS_PRETTY="${PRETTY_NAME:-unknown}"
fi

RGBPI_UI="NO"
[[ -d /opt/rgbpi/ui ]] && RGBPI_UI="YES"

RETROARCH="NO"
[[ -x /opt/retroarch/retroarch ]] && RETROARCH="YES"

TIMINGS="NO"
[[ -f /opt/rgbpi/ui/data/timings.dat ]] && TIMINGS="YES"

SUDO_MODE="restricted-or-unavailable"
if [[ "$EUID" -eq 0 ]]; then
  SUDO_MODE="root"
elif sudo -n true >/dev/null 2>&1; then
  SUDO_MODE="passwordless"
fi

STATUS="SUPPORTED"
WARNINGS=()

if [[ "$ARCH" != "aarch64" ]]; then
  STATUS="UNSUPPORTED"
  WARNINGS+=("Expected aarch64, got $ARCH")
fi

if [[ "$RGBPI_UI" != "YES" ]]; then
  STATUS="UNSUPPORTED"
  WARNINGS+=("/opt/rgbpi/ui was not found")
fi

if [[ "$MODEL" != *"Raspberry Pi 4"* && "$MODEL" != *"Raspberry Pi 400"* ]]; then
  WARNINGS+=("Primary tested target is Raspberry Pi 4/400; detected: $MODEL")
fi

if [[ "$OS_CODENAME" != "bullseye" ]]; then
  WARNINGS+=("OS4 Final 27 is Bullseye-based; detected codename: $OS_CODENAME")
fi

cat <<EOF
RGB-PI 27 UPDATER - PREFLIGHT

STATUS=$STATUS
ARCH=$ARCH
KERNEL=$KERNEL
MODEL=$MODEL
OS_ID=$OS_ID
OS_CODENAME=$OS_CODENAME
OS_PRETTY=$OS_PRETTY
RGBPI_UI=$RGBPI_UI
RETROARCH=$RETROARCH
TIMINGS=$TIMINGS
ROOT_ACCESS=$SUDO_MODE
EOF

if (("${#WARNINGS[@]}" > 0)); then
  echo
  echo "Warnings:"
  for warning in "${WARNINGS[@]}"; do
    echo " - $warning"
  done
fi

if [[ "$STATUS" == "UNSUPPORTED" ]]; then
  exit 2
fi
exit 0
