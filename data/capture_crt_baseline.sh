#!/usr/bin/env bash
# Capture a read-only CRT/RGB-Pi baseline before changing emulator components.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="${DATA_ROOT:-$SCRIPT_DIR}"
APP_ROOT="${APP_ROOT:-$(cd -- "${DATA_ROOT}/.." && pwd)}"
OUT_ROOT="${APP_ROOT}/backups/crt-baseline"
STAMP="$(date +%F_%H%M%S)"
OUT_DIR="${OUT_ROOT}/${STAMP}"

RETROARCH_BIN="/opt/retroarch/retroarch"
TIMINGS_FILE="/opt/rgbpi/ui/data/timings.dat"

mkdir -p "$OUT_DIR"

copy_if_readable() {
  local src="$1" name="$2"
  if [[ -r "$src" ]]; then
    cp -a "$src" "$OUT_DIR/$name"
  fi
}

{
  echo "captured_at=$(date -Is)"
  echo "user=$(id -un 2>/dev/null || echo unknown)"
  echo "uid=$(id -u 2>/dev/null || echo unknown)"
  echo "arch=$(uname -m 2>/dev/null || echo unknown)"
  echo "kernel=$(uname -r 2>/dev/null || echo unknown)"
  echo "model=$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo unknown)"
  if [[ -r /etc/os-release ]]; then
    grep -E '^(PRETTY_NAME|VERSION_CODENAME|ID)=' /etc/os-release || true
  fi
} > "$OUT_DIR/system.txt"

if [[ -x "$RETROARCH_BIN" ]]; then
  "$RETROARCH_BIN" --version > "$OUT_DIR/retroarch-version.txt" 2>&1 || true
  "$RETROARCH_BIN" --features > "$OUT_DIR/retroarch-features.txt" 2>&1 || true
  ldd "$RETROARCH_BIN" > "$OUT_DIR/retroarch-ldd.txt" 2>&1 || true
  sha256sum "$RETROARCH_BIN" > "$OUT_DIR/retroarch.sha256"
  copy_if_readable "$RETROARCH_BIN" "retroarch"
fi

if [[ -r "$TIMINGS_FILE" ]]; then
  sha256sum "$TIMINGS_FILE" > "$OUT_DIR/timings.dat.sha256"
  copy_if_readable "$TIMINGS_FILE" "timings.dat"
fi

copy_if_readable /boot/config.txt boot-config.txt
copy_if_readable /boot/cmdline.txt boot-cmdline.txt
copy_if_readable /opt/rgbpi/ui/data/cores.cfg cores.cfg

{
  echo "=== target files ==="
  stat "$RETROARCH_BIN" "$TIMINGS_FILE" 2>&1 || true
  echo
  echo "=== framebuffer ==="
  fbset -s 2>&1 || true
  echo
  echo "=== DRM connectors ==="
  for f in /sys/class/drm/*/status; do
    [[ -r "$f" ]] || continue
    printf '%s=' "$f"
    cat "$f"
  done
} > "$OUT_DIR/display-state.txt"

(
  cd "$OUT_DIR"
  sha256sum ./* 2>/dev/null | grep -v '/checksums.sha256$' > checksums.sha256 || true
)

ln -sfn "$OUT_DIR" "$OUT_ROOT/latest"

echo "CRT baseline captured."
echo "BASELINE_DIR=$OUT_DIR"
echo "RETROARCH_BACKUP=$OUT_DIR/retroarch"
echo "TIMINGS_BACKUP=$OUT_DIR/timings.dat"
