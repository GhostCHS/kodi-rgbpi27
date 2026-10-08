#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${APP_DIR}/data"
LOG_DIR="${APP_DIR}/logs"
LOG_FILE="${LOG_DIR}/launcher.log"
REPO_OWNER="${REPO_OWNER:-GhostCHS}"
REPO_NAME="${REPO_NAME:-kodi-rgbpi27}"
UPDATE_BRANCH="${UPDATE_BRANCH:-main}"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${UPDATE_BRANCH}}"

RUNTIME_FILES=(
  common.sh
  preflight.sh
  crt_guard.sh
  capture_crt_baseline.sh
  update_kodi.sh
  update_retroarch.sh
  update_cores.sh
  update_timings.sh
  bootstrap_local_metadata.sh
  mount_all.sh
  rgbpi_update_menu.py
)

mkdir -p "$LOG_DIR"

bundled_mode_ready() {
  [[ -f "$DATA_DIR/manifest.json" && -f "$DATA_DIR/kodi.deb" && -f "$DATA_DIR/kodi-omega-peripheral-joystick.tar.gz" ]]
}

export_runtime_env() {
  export APP_ROOT="$APP_DIR"
  export DATA_ROOT="$DATA_DIR"
  export REPO_OWNER REPO_NAME UPDATE_BRANCH RAW_BASE
  export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
  export PYTHONUNBUFFERED=1
  export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-fbcon}"
  export SDL_FBDEV="${SDL_FBDEV:-/dev/fb0}"
  export SDL_NOMOUSE="${SDL_NOMOUSE:-1}"
  if bundled_mode_ready; then
    export FORCE_BUNDLED_MANIFEST=YES
  fi
}

runtime_complete() {
  local file
  for file in "${RUNTIME_FILES[@]}"; do
    [[ -f "$DATA_DIR/$file" ]] || return 1
  done
  [[ -f "$DATA_DIR/manifest.json" ]]
}

bootstrap_runtime() {
  mkdir -p "$DATA_DIR"
  local file url tmp

  url="${RAW_BASE}/manifest.json"
  tmp="${DATA_DIR}/.manifest.json.tmp"
  curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$tmp"
  mv "$tmp" "${DATA_DIR}/manifest.json"

  for file in "${RUNTIME_FILES[@]}"; do
    url="${RAW_BASE}/data/${file}"
    tmp="${DATA_DIR}/.${file}.tmp"
    curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$tmp"
    mv "$tmp" "${DATA_DIR}/${file}"
  done
  chmod +x "$DATA_DIR"/*.sh
}

ensure_runtime() {
  runtime_complete && return 0
  printf 'Bootstrapping updater runtime from %s/%s (%s)\n' "$REPO_OWNER" "$REPO_NAME" "$UPDATE_BRANCH" >>"$LOG_FILE"
  bootstrap_runtime
}

root_command_prefix() {
  if [[ "$EUID" -eq 0 ]]; then
    printf '%s\0' /usr/bin/env
    return 0
  fi
  if sudo -n true >/dev/null 2>&1; then
    printf '%s\0' sudo -n /usr/bin/env
    return 0
  fi
  return 1
}

show_root_required_message() {
  cat <<'EOF'
RGB-PI 27 UPDATER

Installing updates needs root privileges.

RGB-Pi OS4 Final 27 may intentionally restrict sudo for the stock user.
This updater does not change users, passwords, or sudo policy automatically.

Status checks, Preflight, CRT checks and baseline capture work without root.

See docs/ROOT-ACCESS.md in the repository for the supported bootstrap options.
EOF
}

sudo_exec_script() {
  local script="$1"
  shift || true
  ensure_runtime
  export_runtime_env

  local prefix=()
  while IFS= read -r -d '' item; do
    prefix+=("$item")
  done < <(root_command_prefix || true)

  if (("${#prefix[@]}" == 0)); then
    show_root_required_message
    exit 77
  fi

  exec "${prefix[@]}" \
    "APP_ROOT=$APP_ROOT" \
    "DATA_ROOT=$DATA_DIR" \
    "REPO_OWNER=$REPO_OWNER" \
    "REPO_NAME=$REPO_NAME" \
    "UPDATE_BRANCH=$UPDATE_BRANCH" \
    "FORCE_BUNDLED_MANIFEST=${FORCE_BUNDLED_MANIFEST:-NO}" \
    "SDL_AUDIODRIVER=$SDL_AUDIODRIVER" \
    "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" \
    "PYTHONUNBUFFERED=$PYTHONUNBUFFERED" \
    "SDL_VIDEODRIVER=$SDL_VIDEODRIVER" \
    "SDL_FBDEV=$SDL_FBDEV" \
    "SDL_NOMOUSE=$SDL_NOMOUSE" \
    bash "$script" "$@"
}

launch_menu() {
  ensure_runtime
  export_runtime_env
  cd "$APP_DIR"
  exec python3 "$DATA_DIR/rgbpi_update_menu.py" "$@" >>"$LOG_FILE" 2>&1
}

case "${1:-}" in
  --bootstrap-runtime)
    bootstrap_runtime
    ;;
  --dump-status|--terminal)
    ensure_runtime
    export_runtime_env
    exec python3 "$DATA_DIR/rgbpi_update_menu.py" "$@"
    ;;
  preflight)
    ensure_runtime
    export_runtime_env
    exec bash "$DATA_DIR/preflight.sh"
    ;;
  crt-check)
    ensure_runtime
    export_runtime_env
    exec bash "$DATA_DIR/crt_guard.sh" --status
    ;;
  baseline)
    ensure_runtime
    export_runtime_env
    exec bash "$DATA_DIR/capture_crt_baseline.sh"
    ;;
  kodi)
    shift
    sudo_exec_script "$DATA_DIR/update_kodi.sh" "${1:---update}"
    ;;
  retroarch)
    shift
    sudo_exec_script "$DATA_DIR/update_retroarch.sh" "${1:---update}"
    ;;
  cores)
    shift
    sudo_exec_script "$DATA_DIR/update_cores.sh" "${1:---update}"
    ;;
  timings)
    shift
    sudo_exec_script "$DATA_DIR/update_timings.sh" "${1:---update}"
    ;;
  bootstrap)
    shift
    sudo_exec_script "$DATA_DIR/bootstrap_local_metadata.sh" "$@"
    ;;
  mount)
    shift
    sudo_exec_script "$DATA_DIR/mount_all.sh" "$@"
    ;;
  root|make-root|pi-root)
    show_root_required_message
    exit 77
    ;;
  "")
    launch_menu
    ;;
  *)
    cat <<USAGE
Usage:
  ./update.sh                       Launch RGB-Pi 27 updater menu
  ./update.sh preflight             Check OS4 / Pi / architecture compatibility
  ./update.sh crt-check             Check software-side CRT compatibility guards
  ./update.sh baseline              Capture current CRT/RetroArch baseline
  ./update.sh kodi [--status|--update]
  ./update.sh retroarch [--status|--update]
  ./update.sh cores [--status|--update]
  ./update.sh timings [--status|--update]
  ./update.sh bootstrap             Seed local version markers (root required)
  ./update.sh mount [args...]       Run NAS mount helper (root required)
  ./update.sh --dump-status         Print updater status summary
  ./update.sh --bootstrap-runtime   Download the runtime from GitHub
USAGE
    exit 1
    ;;
esac
