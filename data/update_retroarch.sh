#!/usr/bin/env bash
# Manifest-driven RetroArch updater for RGB-Pi.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="${DATA_ROOT:-$SCRIPT_DIR}"
APP_ROOT="${APP_ROOT:-$(cd -- "${DATA_ROOT}/.." && pwd)}"
. "${DATA_ROOT}/common.sh"

DOWNLOAD_DIR="${DATA_ROOT}/debs"
ARCHIVE_PATH="${DOWNLOAD_DIR}/retroarch-rgbpi.tar.gz"
LOG_FILE="/var/log/retroarch-update.log"
LOG_DIR="/var/log/retroarch-updater"
INSTALL_ROOT="/opt/retroarch"
TARGET_BIN="${INSTALL_ROOT}/retroarch"
VERSION_FILE="${INSTALL_ROOT}/.rgbpi-retroarch-version"
DRY_RUN="NO"
MODE="update"
CRT_GUARD_SCRIPT="${DATA_ROOT}/crt_guard.sh"
TIMINGS_FILE="/opt/rgbpi/ui/data/timings.dat"
ALLOW_UNVALIDATED_CRT="${ALLOW_UNVALIDATED_CRT:-NO}"

validate_installed_binary() {
  local log_file="$1"

  [[ -x "$TARGET_BIN" ]] || {
    log "$log_file" "ERROR: installed RetroArch binary is not executable"
    return 1
  }

  [[ -s "$TIMINGS_FILE" ]] || {
    log "$log_file" "ERROR: RGB-Pi timings.dat is missing or empty"
    return 1
  }

  if command -v readelf >/dev/null 2>&1; then
    readelf -h "$TARGET_BIN" 2>/dev/null | grep -q 'Machine:.*AArch64' || {
      log "$log_file" "ERROR: RetroArch binary is not AArch64"
      return 1
    }
  fi

  if command -v ldd >/dev/null 2>&1 && ldd "$TARGET_BIN" 2>&1 | grep -q 'not found'; then
    log "$log_file" "ERROR: RetroArch has unresolved shared libraries"
    return 1
  fi

  local features token graphics_api=""
  features="$("$TARGET_BIN" --features 2>/dev/null || true)"
  [[ -n "$features" ]] || {
    log "$log_file" "ERROR: RetroArch --features produced no usable output"
    return 1
  }

  for token in KMS EGL ALSA UDEV; do
    if ! printf '%s\n' "$features" | grep -Ei "^[[:space:]]*${token}[[:space:]].*yes" >/dev/null; then
      log "$log_file" "ERROR: required CRT/runtime feature is missing: $token"
      return 1
    fi
  done

  if printf '%s\n' "$features" | grep -Ei '^[[:space:]]*OpenGLES[[:space:]].*yes' >/dev/null; then
    graphics_api="OpenGLES"
  elif printf '%s\n' "$features" | grep -Ei '^[[:space:]]*OpenGL[[:space:]].*yes' >/dev/null; then
    graphics_api="OpenGL"
  else
    log "$log_file" "ERROR: required graphics API is missing: OpenGL/OpenGLES"
    return 1
  fi

  log "$log_file" "CRT software guard: KMS/EGL/${graphics_api}/ALSA/UDEV present, timings.dat intact"
  return 0
}


parse_args() {
  case "${1:-}" in
    --status) MODE="status" ;;
    --update|"") MODE="update" ;;
    *) echo "Usage: sudo bash $0 [--status|--update]"; exit 1 ;;
  esac
}

main() {
  parse_args "${1:-}"
  if [[ "$MODE" == "status" && "$(id -u)" -ne 0 ]]; then
    LOG_FILE="${APP_ROOT}/logs/status-retroarch.log"
    LOG_DIR="${APP_ROOT}/logs/status-retroarch"
  else
    require_root
  fi
  mkdir -p "$DOWNLOAD_DIR" "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  set_run_log "$LOG_DIR"

  bar 5 "Preparing RetroArch updater"
  ensure_tooling "$LOG_FILE" "$DRY_RUN"
  bar 15 "Fetching manifest"
  if ! fetch_manifest "$LOG_FILE" "$DRY_RUN"; then
    line
    log "$LOG_FILE" "Available version : unknown"
    emit_status_lines "$(installed_version)" "unknown" "NO"
    exit 1
  fi

  local available filename url checksum binary_checksum validation installed update_flag local_sha fallback_detected
  available="$(manifest_field retroarch version)"
  filename="$(manifest_field retroarch filename)"
  url="$(manifest_field retroarch url)"
  checksum="$(manifest_field retroarch sha256)"
  binary_checksum="$(manifest_field retroarch binary_sha256)"
  validation="$(manifest_field retroarch validation)"
  installed="unknown"
  fallback_detected="NO"

  if [[ -f "$VERSION_FILE" ]]; then
    installed="$(cat "$VERSION_FILE")"
  elif [[ -x "$TARGET_BIN" && -n "$binary_checksum" ]]; then
    local_sha="$(sha256_file "$TARGET_BIN")"
    if [[ "$local_sha" == "$binary_checksum" ]]; then
      installed="$available"
      fallback_detected="YES"
    fi
  fi

  if compare_pkg_update "$installed" "$available" 2>/dev/null || [[ "$installed" == "unknown" && "$available" != "unknown" ]]; then
    update_flag="YES"
  elif [[ "$installed" != "$available" ]]; then
    update_flag="YES"
  else
    update_flag="NO"
  fi

  log "$LOG_FILE" "Installed version : $installed"
  log "$LOG_FILE" "Available version : $available"
  log "$LOG_FILE" "Asset URL          : $url"
  log "$LOG_FILE" "CRT validation     : $validation"
  [[ "$fallback_detected" == "YES" ]] && log "$LOG_FILE" "Detected installed RetroArch via binary checksum"

  if [[ "$MODE" == "status" ]]; then
    bar 100 "Status ready"
    line
    emit_status_lines "$installed" "$available" "$update_flag"
    exit 0
  fi

  if [[ "$update_flag" != "YES" ]]; then
    bar 100 "No update needed"
    line
    log "$LOG_FILE" "No RetroArch update performed."
    exit 0
  fi

  if [[ "$validation" != *crt* && "$ALLOW_UNVALIDATED_CRT" != "YES" ]]; then
    line
    log "$LOG_FILE" "ERROR: refusing RetroArch payload without CRT validation metadata: $validation"
    log "$LOG_FILE" "Set ALLOW_UNVALIDATED_CRT=YES only for deliberate test builds."
    exit 2
  fi

  if [[ ! -s "$TIMINGS_FILE" ]]; then
    line
    log "$LOG_FILE" "ERROR: refusing update because RGB-Pi timings.dat is missing or empty"
    exit 2
  fi

  bar 30 "Downloading RetroArch package"
  if [[ -n "$filename" && -f "${ASSET_ROOT}/${filename}" ]]; then
    run_cmd "$LOG_FILE" "$DRY_RUN" "cp '${ASSET_ROOT}/${filename}' '$ARCHIVE_PATH'"
  else
    download_to_file "$LOG_FILE" "$DRY_RUN" "$url" "$ARCHIVE_PATH"
  fi

  if [[ -n "$checksum" && "$checksum" != "unknown" ]]; then
    local actual
    actual="$(sha256_file "$ARCHIVE_PATH")"
    if [[ "$actual" != "$checksum" ]]; then
      line
      log "$LOG_FILE" "ERROR: checksum mismatch for RetroArch asset"
      exit 1
    fi
  fi

  local tmpdir backup_bin="" old_version="" had_version="NO"
  tmpdir="$(mktemp -d)"

  bar 62 "Extracting RetroArch package"
  run_cmd "$LOG_FILE" "$DRY_RUN" "tar -xzf '$ARCHIVE_PATH' -C '$tmpdir'"

  if [[ ! -f "$tmpdir/retroarch/retroarch" ]]; then
    line
    log "$LOG_FILE" "ERROR: package missing retroarch/retroarch"
    rm -rf "$tmpdir"
    exit 1
  fi

  bar 78 "Creating rollback copy"
  if [[ "$DRY_RUN" != "YES" && -f "$TARGET_BIN" ]]; then
    backup_bin="$(mktemp "${DOWNLOAD_DIR}/retroarch.rollback.XXXXXX")"
    cp -a "$TARGET_BIN" "$backup_bin"
    if [[ -f "$VERSION_FILE" ]]; then
      old_version="$(cat "$VERSION_FILE")"
      had_version="YES"
    fi
    log "$LOG_FILE" "Rollback copy created: $backup_bin"
  fi

  restore_previous_retroarch() {
    if [[ -n "$backup_bin" && -f "$backup_bin" ]]; then
      install -m 0755 "$backup_bin" "$TARGET_BIN"
      if [[ "$had_version" == "YES" ]]; then
        printf '%s\n' "$old_version" > "$VERSION_FILE"
      else
        rm -f "$VERSION_FILE"
      fi
      log "$LOG_FILE" "Previous RetroArch binary restored after failed update"
    fi
  }

  bar 82 "Installing RetroArch binary only (configs/timings untouched)"
  if ! run_cmd "$LOG_FILE" "$DRY_RUN" "install -m 0755 '$tmpdir/retroarch/retroarch' '$TARGET_BIN'"; then
    line
    restore_previous_retroarch
    rm -rf "$tmpdir"
    rm -f "$backup_bin"
    log "$LOG_FILE" "ERROR: RetroArch installation failed; rollback attempted"
    exit 1
  fi

  bar 92 "Checking CRT runtime compatibility"
  if [[ "$DRY_RUN" != "YES" ]] && ! validate_installed_binary "$LOG_FILE"; then
    line
    restore_previous_retroarch
    rm -rf "$tmpdir"
    rm -f "$backup_bin"
    log "$LOG_FILE" "ERROR: installed RetroArch failed CRT/runtime validation; previous binary restored"
    exit 1
  fi

  bar 96 "Recording validated RetroArch version"
  run_cmd "$LOG_FILE" "$DRY_RUN" "printf '%s\n' '$available' > '$VERSION_FILE'"

  rm -rf "$tmpdir"
  rm -f "$backup_bin"
  bar 100 "RetroArch update complete"
  line
  log "$LOG_FILE" "RetroArch update finished"
  emit_status_lines "$(cat "$VERSION_FILE")" "$available" "NO"
}

main "$@"
