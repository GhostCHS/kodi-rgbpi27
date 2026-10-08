#!/usr/bin/env bash
# Non-destructive CRT compatibility guard for RGB-Pi OS4 Final 27.
#
# This verifies the software prerequisites that can be checked automatically.
# It cannot replace a real 15-kHz CRT regression test.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="${DATA_ROOT:-$SCRIPT_DIR}"
APP_ROOT="${APP_ROOT:-$(cd -- "${DATA_ROOT}/.." && pwd)}"
RETROARCH_BIN="/opt/retroarch/retroarch"
RGBPI_UI="/opt/rgbpi/ui"
TIMINGS_FILE="/opt/rgbpi/ui/data/timings.dat"
MANIFEST="${DATA_ROOT}/manifest.json"
MODE="${1:---status}"

case "$MODE" in
  --status|--strict) ;;
  *) echo "Usage: bash $0 [--status|--strict]"; exit 1 ;;
esac

failures=()
warnings=()

ok() { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; warnings+=("$*"); }
fail() { printf 'FAIL %s\n' "$*"; failures+=("$*"); }

arch="$(uname -m 2>/dev/null || echo unknown)"
if [[ "$arch" == "aarch64" ]]; then
  ok "Architecture is aarch64"
else
  fail "Expected aarch64, detected $arch"
fi

model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo unknown)"
if [[ "$model" == *"Raspberry Pi 4"* || "$model" == *"Raspberry Pi 400"* ]]; then
  ok "Target board detected: $model"
else
  warn "Primary CRT target is Raspberry Pi 4/400; detected: $model"
fi

if [[ -d "$RGBPI_UI" ]]; then
  ok "RGB-Pi UI is present"
else
  fail "Missing $RGBPI_UI"
fi

if [[ -s "$TIMINGS_FILE" ]]; then
  ok "RGB-Pi timings.dat is present and non-empty"
else
  fail "Missing or empty $TIMINGS_FILE"
fi

if [[ -x "$RETROARCH_BIN" ]]; then
  ok "RetroArch binary is executable"
else
  fail "Missing executable $RETROARCH_BIN"
fi

if [[ -x "$RETROARCH_BIN" ]]; then
  if command -v readelf >/dev/null 2>&1; then
    if readelf -h "$RETROARCH_BIN" 2>/dev/null | grep -q 'Machine:.*AArch64'; then
      ok "RetroArch binary is AArch64"
    else
      fail "RetroArch binary is not AArch64"
    fi
  else
    warn "readelf not available; binary architecture was not verified"
  fi

  if command -v ldd >/dev/null 2>&1; then
    if ldd "$RETROARCH_BIN" 2>&1 | grep -q 'not found'; then
      fail "RetroArch has unresolved shared libraries"
    else
      ok "RetroArch shared libraries resolve"
    fi
  else
    warn "ldd not available; shared libraries were not verified"
  fi

  features="$("$RETROARCH_BIN" --features 2>/dev/null || true)"
  if [[ -n "$features" ]]; then
    for spec in       'KMS:KMS'       'EGL:EGL'       'OpenGLES:OpenGLES'       'ALSA:ALSA'       'UDEV:UDEV'
    do
      label="${spec%%:*}"
      token="${spec#*:}"
      if printf '%s\n' "$features" | grep -Ei "^[[:space:]]*${token}[[:space:]].*yes" >/dev/null; then
        ok "RetroArch feature enabled: $label"
      else
        fail "RetroArch feature missing/disabled: $label"
      fi
    done
  else
    fail "RetroArch --features returned no usable feature list"
  fi
fi

if [[ -f "$MANIFEST" ]] && command -v python3 >/dev/null 2>&1; then
  manifest_check="$(python3 - "$MANIFEST" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    m=json.load(fh)
policy=m.get("policy",{}).get("stable_requires_crt_validation")
ra=m.get("assets",{}).get("retroarch",{}).get("validation","")
tim=m.get("assets",{}).get("timings",{}).get("validation","")
print("YES" if policy is True else "NO")
print(ra)
print(tim)
PY
)"
  policy="$(printf '%s\n' "$manifest_check" | sed -n '1p')"
  ra_validation="$(printf '%s\n' "$manifest_check" | sed -n '2p')"
  timing_validation="$(printf '%s\n' "$manifest_check" | sed -n '3p')"

  if [[ "$policy" == "YES" ]]; then
    ok "Stable manifest requires CRT validation"
  else
    fail "Stable manifest does not enforce CRT validation policy"
  fi

  if [[ "$ra_validation" == *crt* ]]; then
    ok "Stable RetroArch payload is marked CRT-validated"
  else
    fail "Stable RetroArch payload is not marked CRT-validated"
  fi

  if [[ "$timing_validation" == *rgbpi-os4-final27* ]]; then
    ok "timings.dat payload is marked for OS4 Final 27"
  else
    fail "timings.dat payload is not marked for OS4 Final 27"
  fi
else
  warn "Local manifest unavailable; release policy metadata was not checked"
fi

printf '\nCRT_GUARD_FAILURES=%d\n' "${#failures[@]}"
printf 'CRT_GUARD_WARNINGS=%d\n' "${#warnings[@]}"

if (("${#failures[@]}" == 0)); then
  echo "CRT_GUARD=PASS"
  exit 0
fi

echo "CRT_GUARD=FAIL"
if [[ "$MODE" == "--strict" ]]; then
  exit 2
fi
exit 0
