#!/usr/bin/env bash

set -u

REPO_OWNER="${REPO_OWNER:-GhostCHS}"
REPO_NAME="${REPO_NAME:-kodi-rgbpi27}"
UPDATE_BRANCH="${UPDATE_BRANCH:-main}"
RELEASE_TAG="${RELEASE_TAG:-latest}"
MANIFEST_URL_PRIMARY="${MANIFEST_URL_PRIMARY-https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${UPDATE_BRANCH}/manifest.json}"
MANIFEST_URL_FALLBACK="${MANIFEST_URL_FALLBACK-https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${RELEASE_TAG}/manifest.json}"
FORCE_BUNDLED_MANIFEST="${FORCE_BUNDLED_MANIFEST:-NO}"
SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
DATA_ROOT="${DATA_ROOT:-$SCRIPT_DIR}"
APP_ROOT="${APP_ROOT:-$(cd -- "${DATA_ROOT}/.." && pwd)}"
WORK_ROOT="${WORK_ROOT:-${APP_ROOT}/.updater}"
MANIFEST_CACHE="${MANIFEST_CACHE:-${WORK_ROOT}/manifest.json}"
BUNDLED_MANIFEST="${BUNDLED_MANIFEST:-${DATA_ROOT}/manifest.json}"
ASSET_ROOT="${ASSET_ROOT:-${DATA_ROOT}}"
MANIFEST_CACHE_MAX_AGE="${MANIFEST_CACHE_MAX_AGE:-300}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-15}"
CURL_MAX_TIME="${CURL_MAX_TIME:-90}"
GITHUB_API_TIMEOUT="${GITHUB_API_TIMEOUT:-30}"

bar() {
  local pct="${1:-0}" msg="${2:-}"
  local width=40 fill empty
  fill=$((pct * width / 100))
  empty=$((width - fill))
  printf "\r[%3d%%] [" "$pct"
  if ((fill > 0)); then printf "%0.s#" $(seq 1 "$fill"); fi
  if ((empty > 0)); then printf "%0.s-" $(seq 1 "$empty"); fi
  printf "] %s" "$msg"
}

line() {
  printf "\n%s\n" "$*"
}

set_run_log() {
  local log_dir="$1" ts
  ts="$(date +%F_%H%M%S)"
  mkdir -p "$log_dir"
  RUN_LOG="${log_dir}/run_${ts}.log"
  LATEST_LOG="${log_dir}/latest.log"
  ln -sfn "$RUN_LOG" "$LATEST_LOG"
}

log() {
  local log_file="$1"
  shift
  local ts
  ts="$(date '+%F %T')"
  echo "[$ts] $*" | tee -a "$log_file" "$RUN_LOG"
}

run_cmd() {
  local log_file="$1" dry_run="$2" cmd="$3"
  if [[ "$dry_run" == "YES" ]]; then
    log "$log_file" "DRY-RUN: $cmd"
    return 0
  fi
  eval "$cmd"
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Root privileges are required for this update action."
    echo "Run the updater with a permitted sudo/root setup; see docs/ROOT-ACCESS.md."
    exit 77
  fi
}

ensure_tooling() {
  local log_file="$1" dry_run="$2"
  local missing=()
  local cmd

  for cmd in curl python3 sha256sum tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if (("${#missing[@]}" == 0)); then
    return 0
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    log "$log_file" "ERROR: missing required tools: ${missing[*]}"
    return 1
  fi

  run_cmd "$log_file" "$dry_run" "apt-get update >/dev/null"
  run_cmd "$log_file" "$dry_run" "apt-get install -y ${missing[*]} ca-certificates >/dev/null"
}

validate_manifest() {
  local path="$1"
  python3 - "$path" <<'PY'
import json
import re
import sys
import urllib.parse

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

if data.get("channel") not in {"stable", "preview", "latest"}:
    raise SystemExit("invalid manifest channel")

assets = data.get("assets")
if not isinstance(assets, dict):
    raise SystemExit("manifest has no assets object")

required = ("kodi", "kodi_joystick", "retroarch", "cores", "timings")
allowed_hosts = {"github.com", "api.github.com", "raw.githubusercontent.com"}

for key in required:
    item = assets.get(key)
    if not isinstance(item, dict):
        raise SystemExit(f"manifest missing asset: {key}")
    if not item.get("version"):
        raise SystemExit(f"manifest asset has no version: {key}")

    filename = item.get("filename", "")
    if not isinstance(filename, str) or not filename or "/" in filename or "\\" in filename or filename in {".", ".."}:
        raise SystemExit(f"manifest asset has unsafe filename: {key}")

    digest = item.get("sha256", "")
    if not isinstance(digest, str) or re.fullmatch(r"[0-9a-fA-F]{64}", digest) is None:
        raise SystemExit(f"manifest asset has invalid sha256: {key}")

    binary_digest = item.get("binary_sha256")
    if binary_digest not in (None, "") and (
        not isinstance(binary_digest, str) or re.fullmatch(r"[0-9a-fA-F]{64}", binary_digest) is None
    ):
        raise SystemExit(f"manifest asset has invalid binary_sha256: {key}")

    url = item.get("url", "")
    if not isinstance(url, str) or any(ch in url for ch in ("\r", "\n", "\t", "'", '"', "`", "$")):
        raise SystemExit(f"manifest asset has unsafe URL: {key}")
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in allowed_hosts:
        raise SystemExit(f"manifest asset URL host is not allowed: {key}")

if data.get("channel") == "stable":
    policy = data.get("policy", {})
    if policy.get("stable_requires_crt_validation") is not True:
        raise SystemExit("stable manifest must require CRT validation")

    if "crt" not in str(assets["retroarch"].get("validation", "")).lower():
        raise SystemExit("stable RetroArch asset lacks CRT validation metadata")

    if "crt" not in str(assets["cores"].get("validation", "")).lower():
        raise SystemExit("stable core bundle lacks CRT validation metadata")

    if "rgbpi-os4-final27" not in str(assets["timings"].get("validation", "")).lower():
        raise SystemExit("stable timings.dat is not marked for RGB-Pi OS4 Final 27")
PY
}

github_release_asset_api_url() {
  local url="$1"
  local owner repo tag filename release_endpoint encoded_tag release_json asset_id

  if [[ ! "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^/?#]+)$ ]]; then
    return 1
  fi

  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  tag="${BASH_REMATCH[3]}"
  filename="${BASH_REMATCH[4]}"

  encoded_tag="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$tag")"
  release_endpoint="https://api.github.com/repos/${owner}/${repo}/releases/tags/${encoded_tag}"

  release_json="$(curl -fsSL -sS --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$GITHUB_API_TIMEOUT" "$release_endpoint" 2>/dev/null)" || return 1
  asset_id="$(
    printf '%s' "$release_json" | python3 -c '
import json, sys
name = sys.argv[1]
try:
    release = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
for asset in release.get("assets", []):
    if asset.get("name") == name and asset.get("state") == "uploaded":
        print(asset.get("id", ""))
        raise SystemExit(0)
raise SystemExit(1)
' "$filename"
  )" || return 1

  [[ -n "$asset_id" ]] || return 1
  printf 'https://api.github.com/repos/%s/%s/releases/assets/%s\n' "$owner" "$repo" "$asset_id"
}

download_to_file() {
  local log_file="$1" dry_run="$2" url="$3" destination="$4"
  local tmp direct_rc=0 api_url="" attempt rc=1
  tmp="${destination}.part.${BASHPID}"

  if [[ "$dry_run" == "YES" ]]; then
    log "$log_file" "DRY-RUN: download $url -> $destination"
    return 0
  fi

  mkdir -p "$(dirname "$destination")"
  rm -f "$tmp"

  curl -fL -sS \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    "$url" -o "$tmp" || direct_rc=$?

  if ((direct_rc == 0)); then
    mv -f "$tmp" "$destination"
    return 0
  fi

  rm -f "$tmp"
  log "$log_file" "WARN: direct download failed (curl exit $direct_rc): $url"

  api_url="$(github_release_asset_api_url "$url" || true)"
  if [[ -n "$api_url" ]]; then
    log "$log_file" "Trying GitHub release-asset API fallback"
    for attempt in 1 2; do
      rc=0
      curl -fL -sS \
        -H 'Accept: application/octet-stream' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        --connect-timeout "$CURL_CONNECT_TIMEOUT" \
        --max-time "$CURL_MAX_TIME" \
        "$api_url" -o "$tmp" || rc=$?
      if ((rc == 0)); then
        mv -f "$tmp" "$destination"
        log "$log_file" "GitHub API fallback succeeded"
        return 0
      fi
      rm -f "$tmp"
      ((attempt < 2)) && sleep 2
    done
  fi

  rm -f "$tmp"
  log "$log_file" "ERROR: download failed after fallback attempts: $url"
  return 1
}

fetch_manifest() {
  local log_file="$1" dry_run="$2"
  mkdir -p "$WORK_ROOT"

  if [[ "$dry_run" == "YES" ]]; then
    log "$log_file" "DRY-RUN: would fetch manifest to $MANIFEST_CACHE"
    cp "$BUNDLED_MANIFEST" "$MANIFEST_CACHE" 2>/dev/null || true
    [[ -f "$MANIFEST_CACHE" ]] && validate_manifest "$MANIFEST_CACHE"
    return 0
  fi

  if [[ "$FORCE_BUNDLED_MANIFEST" == "YES" && -f "$BUNDLED_MANIFEST" ]]; then
    cp "$BUNDLED_MANIFEST" "$MANIFEST_CACHE"
    validate_manifest "$MANIFEST_CACHE"
    log "$log_file" "manifest_source=$BUNDLED_MANIFEST (forced)"
    return 0
  fi

  if [[ -f "$MANIFEST_CACHE" ]]; then
    local now cache_age
    now="$(date +%s)"
    cache_age=$((now - $(stat -c %Y "$MANIFEST_CACHE" 2>/dev/null || echo 0)))
    if ((cache_age >= 0 && cache_age < MANIFEST_CACHE_MAX_AGE)); then
      if validate_manifest "$MANIFEST_CACHE" >/dev/null 2>&1; then
        log "$log_file" "manifest_source=$MANIFEST_CACHE (cached ${cache_age}s)"
        return 0
      fi
      rm -f "$MANIFEST_CACHE"
    fi
  fi

  if [[ -n "$MANIFEST_URL_PRIMARY" ]] && curl -fsSL -sS --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$GITHUB_API_TIMEOUT" "$MANIFEST_URL_PRIMARY" -o "$MANIFEST_CACHE"; then
    if validate_manifest "$MANIFEST_CACHE" >/dev/null 2>&1; then
      log "$log_file" "manifest_source=$MANIFEST_URL_PRIMARY"
      return 0
    fi
    rm -f "$MANIFEST_CACHE"
  fi

  if [[ -n "$MANIFEST_URL_FALLBACK" ]] && curl -fsSL -sS --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$GITHUB_API_TIMEOUT" "$MANIFEST_URL_FALLBACK" -o "$MANIFEST_CACHE"; then
    if validate_manifest "$MANIFEST_CACHE" >/dev/null 2>&1; then
      log "$log_file" "manifest_source=$MANIFEST_URL_FALLBACK"
      return 0
    fi
    rm -f "$MANIFEST_CACHE"
  fi

  if [[ -f "$BUNDLED_MANIFEST" ]]; then
    cp "$BUNDLED_MANIFEST" "$MANIFEST_CACHE"
    validate_manifest "$MANIFEST_CACHE"
    log "$log_file" "manifest_source=$BUNDLED_MANIFEST"
    return 0
  fi

  log "$log_file" "ERROR: unable to fetch a valid manifest"
  return 1
}

manifest_field() {
  local key="$1" field="$2"
  python3 - "$MANIFEST_CACHE" "$key" "$field" <<'PY'
import json
import sys

path, key, field = sys.argv[1:]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
value = data.get("assets", {}).get(key, {}).get(field, "")
if value is None:
    value = ""
print(value)
PY
}

manifest_top_field() {
  local field="$1"
  python3 - "$MANIFEST_CACHE" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1:]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
value = data.get(field, "")
if isinstance(value, (dict, list)):
    print(json.dumps(value, separators=(",", ":")))
else:
    print(value)
PY
}

emit_status_lines() {
  local installed="$1" available="$2" update_available="$3"
  echo "INSTALLED_VERSION=${installed}"
  echo "AVAILABLE_VERSION=${available}"
  echo "UPDATE_AVAILABLE=${update_available}"
}

sha256_file() {
  local path="$1"
  sha256sum "$path" | awk '{print $1}'
}

compare_exact_update() {
  local installed="$1" available="$2"
  [[ "$installed" != "$available" ]]
}

compare_pkg_update() {
  local installed="$1" available="$2"
  if [[ "$installed" == "not-installed" || "$installed" == "unknown" || -z "$installed" ]]; then
    return 0
  fi
  if command -v dpkg >/dev/null 2>&1 && dpkg --compare-versions "$available" gt "$installed" 2>/dev/null; then
    return 0
  fi
  [[ "$installed" != "$available" ]]
}
