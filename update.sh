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
ACTIVE_TTY="${ACTIVE_TTY:-$(cat /sys/class/tty/tty0/active 2>/dev/null | tr -d '[:space:]')}"
ACTIVE_TTY="${ACTIVE_TTY:-tty1}"

RUNTIME_FILES=(
  common.sh
  preflight.sh
  crt_guard.sh
  update_retroarch.sh
  update_cores.sh
  update_timings.sh
  bootstrap_local_metadata.sh
  mount_all.sh
  rgbpi_update_menu.py
)

mkdir -p "$LOG_DIR"

bundled_mode_ready() {
  [[ -f "$DATA_DIR/manifest.json" && -f "$DATA_DIR/retroarch-rgbpi.tar.gz" && -f "$DATA_DIR/cores.tar.gz" ]]
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

sudo_env_args() {
  printf '%s\0' \
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
    "SDL_NOMOUSE=$SDL_NOMOUSE"
}

show_privilege_required_message() {
  cat <<EOF
RGB-PI 27 UPDATER

Launch this updater from RGB-Pi's Ports menu for installation actions.
The OS4 frontend already runs Ports as root; no sudoers change is needed.
SSH user pi can run preflight, crt-check and --dump-status.
For terminal updates, use an administrator-authorized root shell.
No password or privilege policy is changed by this updater.
EOF
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
  curl -fsSL --connect-timeout 15 "$url" -o "$tmp"
  mv "$tmp" "${DATA_DIR}/manifest.json"

  for file in "${RUNTIME_FILES[@]}"; do
    url="${RAW_BASE}/data/${file}"
    tmp="${DATA_DIR}/.${file}.tmp"
    curl -fsSL --connect-timeout 15 "$url" -o "$tmp"
    mv "$tmp" "${DATA_DIR}/${file}"
  done
  chmod +x "$DATA_DIR"/*.sh
}

ensure_runtime() {
  runtime_complete && return 0
  printf 'Bootstrapping updater runtime from %s/%s (%s)\n' "$REPO_OWNER" "$REPO_NAME" "$UPDATE_BRANCH" >>"$LOG_FILE"
  bootstrap_runtime
}

require_update_privileges() {
  [[ "$EUID" -eq 0 ]] && return 0
  # Probe the actual command class used below, not unrelated `sudo true`.
  sudo -n /usr/bin/env bash -c 'test "$EUID" -eq 0' >/dev/null 2>&1 && return 0
  show_privilege_required_message
  exit 77
}

sudo_exec_script() {
  local script="$1"
  shift || true
  ensure_runtime
  export_runtime_env
  require_update_privileges

  local env_args=()
  while IFS= read -r -d '' arg; do
    env_args+=("$arg")
  done < <(sudo_env_args)

  if [[ "$EUID" -eq 0 ]]; then
    exec /usr/bin/env "${env_args[@]}" bash "$script" "$@"
  fi
  exec sudo -n /usr/bin/env "${env_args[@]}" bash "$script" "$@"
}

launch_menu() {
  ensure_runtime
  export_runtime_env
  require_update_privileges

  CURRENT_TTY="$(readlink -f /proc/self/fd/0 2>/dev/null || true)"
  if [[ "$EUID" -ne 0 || "$CURRENT_TTY" != "/dev/${ACTIVE_TTY}" ]]; then
    local env_args=()
    while IFS= read -r -d '' arg; do
      env_args+=("$arg")
    done < <(sudo_env_args)

    local privilege_prefix=()
    [[ "$EUID" -eq 0 ]] || privilege_prefix=(sudo -n)
    exec "${privilege_prefix[@]}" /usr/bin/env \
      ACTIVE_TTY="$ACTIVE_TTY" \
      "${env_args[@]}" \
      bash -lc 'exec </dev/"$ACTIVE_TTY" >/dev/"$ACTIVE_TTY" 2>&1; exec "$0" __menu_internal "$@"' \
      "$APP_DIR/update.sh" "$@"
  fi

  cd "$APP_DIR"
  exec python3 "$DATA_DIR/rgbpi_update_menu.py" "$@" >>"$LOG_FILE" 2>&1
}

case "${1:-}" in
  __menu_internal)
    shift
    launch_menu "$@"
    ;;
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
  root|make-root|pi-root)
    echo "Automatic sudoers changes have been removed. Launch from RGB-Pi Ports."
    exit 77
    ;;
  bootstrap)
    shift
    sudo_exec_script "$DATA_DIR/bootstrap_local_metadata.sh" "$@"
    ;;
  mount)
    shift
    sudo_exec_script "$DATA_DIR/mount_all.sh" "$@"
    ;;
  "")
    launch_menu
    ;;
  *)
    cat <<USAGE
Usage:
  ./update.sh                       Launch RGB-Pi 27 updater menu
  ./update.sh preflight             Check OS4 / Pi / architecture compatibility
  ./update.sh crt-check             Check software-side CRT compatibility
  ./update.sh retroarch [--status|--update]
  ./update.sh cores [--status|--update]
  ./update.sh timings [--status|--update]
  ./update.sh bootstrap             Seed local version markers
  ./update.sh mount [args...]       Run NAS mount helper
  ./update.sh --dump-status         Print updater status summary
  ./update.sh --bootstrap-runtime   Download the runtime from GitHub
USAGE
    exit 1
    ;;
esac
