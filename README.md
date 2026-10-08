# RGB-Pi 27 Updater

A maintained fork of `joeblack2k/kodi-rgbpi` for **RGB-Pi OS4 Final 27** on Raspberry Pi 4 / Pi 400.

The goal is to modernize selected user-space components without turning OS4 into a rolling Debian installation. RGB-Pi depends on a tightly coupled 15-kHz CRT/DPI stack, so kernel, firmware and base-distribution upgrades are intentionally outside this updater.

## Current policy

**Stable means CRT-tested first, not simply newest.**

As of 2026-10-08:

| Component | Upstream stable | RGB-Pi 27 stable channel |
|---|---:|---:|
| Kodi | 21.3 Omega | 21.3 RGB-Pi build |
| RetroArch | 1.22.2 | 1.22.0-rgbpi1 until 1.22.2 passes real CRT validation |
| Cores | rolling | validated bundle |
| timings.dat | RGB-Pi-specific | validated OS4 Final 27 bundle |

RetroArch 1.22.2 is available only as an experimental build until a real Raspberry Pi 4 + RGB-Pi cable + 15-kHz CRT test passes.

## What this fork changes

- targets `GhostCHS/kodi-rgbpi27` for runtime updates;
- adds OS4 / Pi 4 / AArch64 preflight checks;
- adds a software-side CRT compatibility guard;
- captures a CRT baseline automatically before a one-button update;
- keeps SHA-256 validation for downloadable payloads;
- keeps rollback backups before component replacement;
- rolls RetroArch back automatically if post-install CRT/runtime validation fails;
- shows current task, percentage, elapsed time, last-output age and process-tree CPU activity during long updates;
- does not change users, passwords or sudo policy;
- does not run `apt full-upgrade`, `rpi-update`, kernel replacement or firmware replacement.

## Installation path

The preferred logical path is:

```text
/roms/ports/RGB-PI Updater27
```

Stock RGB-Pi OS4 Final 27 can expose the ROM partition instead at the system-wide mount point:

```text
/media/sd/roms/ports/RGB-PI Updater27
```

`/media/sd` is not tied to the login user; it is the OS4 storage mount. The updater itself is location-independent and resolves its runtime relative to `update.sh`.

For a stock Final 27 system where `/roms` does not exist:

```bash
mkdir -p "/media/sd/roms/ports/RGB-PI Updater27"

curl -fsSL \
  "https://raw.githubusercontent.com/GhostCHS/kodi-rgbpi27/main/update.sh" \
  -o "/media/sd/roms/ports/RGB-PI Updater27/update.sh"

chmod +x "/media/sd/roms/ports/RGB-PI Updater27/update.sh"
```

Then run **Scan Games** in RGB-Pi and open **Ports → RGB-PI Updater27**.

## Safe first-hardware test

Before installing any component:

```bash
"/media/sd/roms/ports/RGB-PI Updater27/update.sh" --bootstrap-runtime
"/media/sd/roms/ports/RGB-PI Updater27/update.sh" preflight
"/media/sd/roms/ports/RGB-PI Updater27/update.sh" crt-check
"/media/sd/roms/ports/RGB-PI Updater27/update.sh" baseline
"/media/sd/roms/ports/RGB-PI Updater27/update.sh" --dump-status
```

These commands do not modify the OS4 kernel, firmware, RetroArch binary, cores or timings. `baseline` only copies the current readable CRT-critical state into the updater folder.

Baseline snapshots are stored under:

```text
RGB-PI Updater27/backups/crt-baseline/
```

They include the current RetroArch binary, `timings.dat`, hashes, RetroArch features, shared-library report and available boot/display information.

## CRT compatibility guard

Run:

```bash
"./update.sh" crt-check
```

The guard verifies the software-side invariants that can be checked without a physical oscilloscope or capture device:

- AArch64 target;
- RGB-Pi UI present;
- non-empty `/opt/rgbpi/ui/data/timings.dat`;
- AArch64 RetroArch binary;
- no unresolved RetroArch shared libraries;
- KMS, EGL, OpenGLES, ALSA and UDEV features;
- stable manifest still requires CRT validation;
- stable RetroArch/core payloads retain CRT validation metadata;
- stable `timings.dat` remains explicitly marked for OS4 Final 27.

A passing software guard is **not** proof of correct 15-kHz output. Real hardware validation remains mandatory.

## One-button update

The framebuffer UI has one update action:

```text
UPDATE EVERYTHING
```

One press updates every component that is actually outdated, in this order:

```text
CRT baseline
Kodi
RetroArch
Cores
CRT timings
CRT verification
```

Steps that are already current are skipped. The stable manifest and each component updater still enforce their normal checks, SHA-256 validation and rollback rules. CRT timings are therefore included in the complete update, but only the OS4 Final 27 validated timings payload can be installed.

## RetroArch update safety

The stable RetroArch updater replaces only:

```text
/opt/retroarch/retroarch
```

It does not intentionally replace RGB-Pi configuration, DynaRes configuration or `timings.dat`.

Before replacement it stores a rollback copy. After installation it validates the new binary and CRT/runtime prerequisites. A failed check restores the previous binary and version marker automatically.

## Progress display

Long-running update screens show:

```text
current operation
percentage
spinner
CPU active / waiting-I/O
elapsed time
seconds since last command output
```

This is intended to distinguish a Pi that is still computing from a process that is only waiting or has stopped producing output.

## Root access

Status, Preflight, CRT checks and baseline capture work without root.

Component installation still needs root privileges. Stock OS4 Final 27 may deliberately restrict the `pi` account. User/password changes are intentionally deferred and are not performed by this project at this stage.

See [docs/ROOT-ACCESS.md](docs/ROOT-ACCESS.md).

## RetroArch 1.22.2 experimental

The reproducible ARM64/Bullseye experimental build is documented in [docs/RETROARCH-EXPERIMENTAL.md](docs/RETROARCH-EXPERIMENTAL.md).

It is not in the stable manifest until physical CRT testing covers at least:

- 240p NTSC around 59.94/60 Hz;
- 288p PAL at 50 Hz;
- NES, SNES, Mega Drive, PlayStation, arcade and N64;
- mode changes / DynaRes;
- audio synchronization;
- controller reconnect;
- game → RGB-Pi menu return.

See [docs/RELEASE-POLICY.md](docs/RELEASE-POLICY.md).

## RGBPi-Extra

RGBPi-Extra is a separate project. It remains useful for additional systems, cores and tweaks. Avoid having two tools replace the same core bundle without a known rollback point.
