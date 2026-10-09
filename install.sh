#!/usr/bin/env bash
# Run from an extracted release/checkout as pi. No system policy changes.
set -euo pipefail
SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
(( $# <= 1 )) || { echo 'Usage: bash install.sh [ports-directory]' >&2; exit 2; }
if (( $# == 1 )); then
  PORTS="$1"
elif [[ -d /media/sd/roms ]]; then
  PORTS=/media/sd/roms/ports
elif [[ -d /roms ]]; then
  PORTS=/roms/ports
else
  echo 'ROM storage not found. Supply the existing roms/ports directory.' >&2
  exit 1
fi
[[ -d "$(dirname -- "$PORTS")" ]] || { echo 'ROM directory must already exist.' >&2; exit 1; }
mkdir -p -- "$PORTS"
PORTS="$(cd -- "$PORTS" && pwd -P)"
[[ "$(basename -- "$PORTS")" == ports && "$(basename -- "$(dirname -- "$PORTS")")" == roms ]] || {
  echo 'Expected an existing storage/roms/ports layout.' >&2; exit 1;
}
STORAGE="$(dirname -- "$(dirname -- "$PORTS")")"
RUNTIME="$STORAGE/.rgbpi-updater27"
TARGET="$PORTS/RGB-PI Updater27"
[[ ! -L "$TARGET" && ! -L "$RUNTIME" ]] || { echo 'Refusing symlink installation targets.' >&2; exit 1; }
[[ "$SOURCE" != "$TARGET" && "$SOURCE" != "$RUNTIME" ]] || { echo 'Install from a separate extracted release.' >&2; exit 1; }
# Stage before replacing runtime files. Never run while an updater is active.
STAGE="$(mktemp -d "$STORAGE/.updater27-install.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
mkdir -p "$STAGE/data"
cp -- "$SOURCE/update.sh" "$STAGE/update.sh"
cp -- "$SOURCE"/data/*.sh "$SOURCE"/data/*.py "$STAGE/data/"
cp -- "$SOURCE/manifest.json" "$STAGE/data/manifest.json"
chmod 0755 "$STAGE/update.sh" "$STAGE"/data/*.sh
[[ ! -L "$RUNTIME/data" ]] || { echo "Refusing symlink runtime data." >&2; exit 1; }
mkdir -p -- "$RUNTIME/data"
# Move an older in-Ports runtime outside scanned ROMs, keeping all old files.
# Refuse unexpected directory contents rather than overwriting another port.
if [[ -e "$TARGET" && ! -f "$TARGET/.updater27-port" ]]; then
  [[ -f "$TARGET/update.sh" && -d "$TARGET/data" ]] || {
    echo 'Existing port is unrecognized; move it aside manually.' >&2; exit 1;
  }
  BACKUP="$(mktemp -d "$RUNTIME/legacy.XXXXXX")"
  mv -- "$TARGET" "$BACKUP/port"
  echo "Previous installation preserved: $BACKUP/port"
fi
cp -- "$STAGE"/data/* "$RUNTIME/data/"
mv -f -- "$STAGE/update.sh" "$RUNTIME/update.sh"
mkdir -p -- "$TARGET"
cat > "$STAGE/port.sh" <<'PORT'
#!/usr/bin/env bash
set -euo pipefail
PORT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$PORT_DIR/../../../.rgbpi-updater27/update.sh" "$@"
PORT
chmod 0755 "$STAGE/port.sh"
mv -f -- "$STAGE/port.sh" "$TARGET/update.sh"
touch "$TARGET/.updater27-port"
# Remove only stale helper rows left by the former in-Ports layout. Preserve
# games.dat owner/mode by writing filtered bytes back to the existing inode.
python3 - "$STORAGE/dats/games.dat" "$RUNTIME/games.dat.before-updater27-cleanup" <<'PY_CLEAN'
import os, pathlib, sys
path = pathlib.Path(sys.argv[1])
backup = pathlib.Path(sys.argv[2])
if path.is_file():
    original = path.read_bytes()
    lines = original.splitlines(keepends=True)
    stale = b"/roms/ports/RGB-PI Updater27/data/"
    kept = [line for line in lines if stale not in line]
    if len(kept) != len(lines):
        if not any(b"/roms/ports/RGB-PI Updater27/update.sh" in line for line in kept):
            raise SystemExit("Refusing games.dat cleanup: updater launch entry is missing")
        if not backup.exists():
            with backup.open("xb") as out:
                out.write(original)
                out.flush()
                os.fsync(out.fileno())
        with path.open("r+b") as out:
            out.seek(0)
            out.write(b"".join(kept))
            out.truncate()
            out.flush()
            os.fsync(out.fileno())
        print("Removed stale Updater27 helper entries; original games.dat backed up.")
PY_CLEAN
printf 'Installed: %s\nRuntime: %s\nRun Scan Games, then Ports -> RGB-PI Updater27 -> update.\n' "$TARGET" "$RUNTIME"
