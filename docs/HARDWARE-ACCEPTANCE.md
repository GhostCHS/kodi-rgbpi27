# PR #18 hardware acceptance: RGB-Pi OS4 Final 27

Do not merge PR #18 until this checklist has passed on a real Raspberry Pi 4/400 with RGB-Pi OS4 Final 27 and a physical 15-kHz CRT.

The purpose of this acceptance is to validate the new Ports-root installation path. It must not change sudoers, kernel, firmware, boot configuration or CRT timings.

## 1. Install the PR build

Use a checkout or extracted archive of branch `fix/os4-final27-ports-installer`.

On the running Pi:

```bash
cd /tmp
rm -rf kodi-rgbpi27-pr18
git clone --depth 1 --branch fix/os4-final27-ports-installer \
  https://github.com/GhostCHS/kodi-rgbpi27.git kodi-rgbpi27-pr18
cd kodi-rgbpi27-pr18
bash install.sh
```

If the card is mounted on another Linux system, pass the mounted Ports directory explicitly:

```bash
bash install.sh /path/to/rootfs/media/sd/roms/ports
```

Expected result:

- runtime: `/media/sd/.rgbpi-updater27` on stock Final 27;
- launcher: `/media/sd/roms/ports/RGB-PI Updater27/update.sh`;
- only one `.sh` file remains below the Updater27 Ports directory;
- no sudoers file is created or modified.

## 2. Capture the pre-test baseline over SSH

Run as the normal `pi` user:

```bash
RUNTIME=/media/sd/.rgbpi-updater27
mkdir -p "$RUNTIME/acceptance"

uname -a | tee "$RUNTIME/acceptance/uname.before"
sha256sum \
  /opt/retroarch/retroarch \
  /opt/rgbpi/ui/data/timings.dat \
  | tee "$RUNTIME/acceptance/hashes.before"

find /etc/sudoers.d -maxdepth 1 -type f -printf '%f %m %u %g\n' 2>/dev/null \
  | sort | tee "$RUNTIME/acceptance/sudoers.before"

bash "$RUNTIME/update.sh" preflight \
  | tee "$RUNTIME/acceptance/preflight.ssh"

bash "$RUNTIME/update.sh" crt-check \
  | tee "$RUNTIME/acceptance/crt-check.before"

bash "$RUNTIME/update.sh" --dump-status \
  | tee "$RUNTIME/acceptance/status.before"
```

Expected over SSH:

- `STATUS=SUPPORTED`;
- `ARCH=aarch64`;
- Raspberry Pi 4/400 detected;
- `CRT_GUARD=PASS`;
- restricted root access for `pi` is acceptable and expected.

## 3. Validate the Ports root context

In RGB-Pi:

1. Run **Scan Games**.
2. Open **Ports -> RGB-PI Updater27 -> update**.
3. Open **System**.
4. Confirm **GUI root: READY**.
5. Run **Preflight** and confirm the system is supported.
6. Run **CRT Check** and confirm it passes.
7. Run **Bootstrap Metadata** once.

Bootstrap Metadata is the non-destructive privilege-path test: it may create/update local version-marker files, but it must not replace RetroArch, cores or `timings.dat`.

A failure here blocks the PR.

## 4. Test UPDATE ALL RETROARCH

From the Updater27 main screen run **UPDATE ALL RETROARCH**.

Expected behavior:

- only RetroArch and cores are considered;
- Kodi is never offered or invoked;
- CRT timings are not updated;
- no sudo password prompt appears;
- no sudoers bootstrap/reboot request appears;
- downloads use checksum validation;
- each completed step is logged;
- the UI remains responsive and returns cleanly after completion.

If both installed assets are already current, a clean no-op is acceptable for this PR, provided the Ports root-context test above passed. Do not force a binary replacement merely to exercise the installer.

## 5. Verify system invariants after the updater run

Over SSH:

```bash
RUNTIME=/media/sd/.rgbpi-updater27

uname -a | tee "$RUNTIME/acceptance/uname.after"
sha256sum /opt/rgbpi/ui/data/timings.dat \
  | tee "$RUNTIME/acceptance/timings.after"

find /etc/sudoers.d -maxdepth 1 -type f -printf '%f %m %u %g\n' 2>/dev/null \
  | sort | tee "$RUNTIME/acceptance/sudoers.after"

bash "$RUNTIME/update.sh" preflight \
  | tee "$RUNTIME/acceptance/preflight.after"

bash "$RUNTIME/update.sh" crt-check \
  | tee "$RUNTIME/acceptance/crt-check.after"

bash "$RUNTIME/update.sh" --dump-status \
  | tee "$RUNTIME/acceptance/status.after"
```

Required invariants:

- `timings.dat` SHA-256 is identical to the pre-test value;
- kernel string is unchanged;
- sudoers file list/modes/owners are unchanged;
- `CRT_GUARD=PASS`;
- RetroArch launches and returns to RGB-Pi normally.

## 6. Physical CRT regression

Test on the actual RGB-Pi cable and 15-kHz CRT.

| Test | Required result |
|---|---|
| 240p NTSC ~59.94/60 Hz | Stable picture, correct geometry, no new flicker |
| 288p PAL 50 Hz | Stable picture, correct geometry, no new flicker |
| NES | Launch, gameplay, audio, exit all normal |
| SNES | Launch, gameplay, audio, exit all normal |
| Mega Drive | Launch, gameplay, audio, exit all normal |
| PlayStation | Launch, gameplay, audio, exit all normal |
| Arcade / FBNeo | Launch, gameplay, audio, exit all normal |
| N64 | Launch, gameplay, audio, exit all normal |
| DynaRes / mode changes | No loss of sync or corrupted mode |
| Audio synchronization | No new drift, crackle or persistent desync |
| Controller reconnect | Input recovers normally |
| Game -> RGB-Pi menu | Clean return with correct video mode |

Known pre-existing title-specific behavior should be documented separately and must not be misclassified as a regression unless PR #18 changes it.

## 7. Merge gate

PR #18 may leave Draft only after all of the following are true:

- GitHub Actions passes on the PR head;
- installation from a clean/legacy Final 27 layout passes;
- Ports reports root context ready without changing sudoers;
- preflight passes;
- CRT software guard passes before and after;
- `timings.dat`, kernel and sudoers invariants hold;
- the physical 240p/288p CRT matrix above passes.

Until then: **do not merge**.
