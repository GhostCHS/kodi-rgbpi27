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
- keeps SHA-256 validation for downloadable payloads;
- updates managed components directly without component backups or rollback copies;
- validates RetroArch after installation and reports any CRT/runtime failure;
- shows current task, percentage, elapsed time, last-output age and process-tree CPU activity during long updates;
- follows the original RGB-Pi first-run privilege bootstrap so the updater can run non-interactively;
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
- KMS, EGL, ALSA and UDEV plus either OpenGL or OpenGLES;
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
Kodi
RetroArch
Cores
CRT timings
CRT verification
```

Each component checks its installed version and becomes a no-op when already current. Downloads are SHA-256 checked, then installed directly. There is no automatic component backup or rollback stage. Each component gets one attempt: if a step exits with an error, it is logged as skipped and UPDATE EVERYTHING continues with the next component. Failed downloads are not retried. A step that does not finish within five minutes is terminated, logged as skipped, and the updater continues.

## RetroArch update safety

The stable RetroArch updater replaces only:

```text
/opt/retroarch/retroarch
```

It does not intentionally replace RGB-Pi configuration, DynaRes configuration or `timings.dat`.

After installation it validates the new binary and CRT/runtime prerequisites. A failed check stops the update and is reported; the updater does not restore an older binary automatically.

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

Component installation needs root privileges. Updater27 follows the original RGB-Pi updater behavior: on first normal launch it attempts to enable passwordless sudo for the stock `pi` account, asks for a reboot, and then runs future updater launches non-interactively with root privileges.

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
