# RGB-Pi 27 Updater

A focused **RetroArch and libretro core updater** for **RGB-Pi OS4 Final 27** on Raspberry Pi 4 / Pi 400, based on `joeblack2k/kodi-rgbpi`.

The updater keeps the original RGB-Pi CRT environment intact while allowing validated RetroArch and core updates. **Kodi is not managed.** Kernel, firmware, base-distribution and automatic CRT timing upgrades are intentionally outside the one-button update path.

## Current policy

**Stable means CRT-tested first, not simply newest.**

As of 2026-10-08:

| Component | Upstream stable | RGB-Pi 27 stable channel |
|---|---:|---:|
| RetroArch | 1.22.2 | 1.22.0-rgbpi1 until 1.22.2 passes real CRT validation |
| Cores | rolling | validated bundle |
| timings.dat | RGB-Pi-specific | validated OS4 Final 27 bundle |

RetroArch 1.22.2 is available only as an experimental build until a real Raspberry Pi 4 + RGB-Pi cable + 15-kHz CRT test passes.

## What this fork changes

- targets RGB-Pi OS4 Final 27 on Raspberry Pi 4 / Pi 400 (AArch64);
- adds OS4 / Pi 4 / AArch64 preflight checks;
- adds a software-side CRT compatibility guard;
- keeps SHA-256 validation for downloadable payloads;
- keeps the one-button update limited to RetroArch and libretro cores;
- validates RetroArch after installation and reports any CRT/runtime failure;
- shows current task, percentage, elapsed time, last-output age and process-tree CPU activity during long updates;
- uses the existing root context of the RGB-Pi Ports launcher; never changes sudoers;
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

`/media/sd` is not tied to the login user; it is the OS4 storage mount. The updater itself is location-independent and resolves its runtime relative to `update.sh`. The installed Port is a wrapper; the runtime
lives outside the scanned ROM tree at `<storage>/.rgbpi-updater27`.

Download and extract a reviewed release or this repository on your PC or Pi.
From the extracted folder, run as the normal `pi` user:

```bash
bash install.sh
```

The installer uses `/media/sd/roms/ports` (or `/roms/ports` when present).
You can supply another existing ROM storage location:

```bash
bash install.sh /media/usb1/roms/ports
```

For a card mounted on a Linux PC, explicitly supply its ROM path, for example
`bash install.sh /mnt/rgbpi-rootfs/media/sd/roms/ports`. The installer
updates only the Updater27 files and removes stale `games.dat` entries that
point at the old in-Ports helper scripts. It backs up the original
`games.dat` under `.rgbpi-updater27/` before editing it. It never modifies
sudoers, startup, kernel, firmware or CRT timings. Do not install while an
updater is running. Run **Scan Games**, then open
**Ports → RGB-PI Updater27 → update** (the exact label depends on folder view).

Ports on the inspected Final 27 installation inherit root from the frontend.
The updater uses that context directly, without granting SSH user `pi` general
sudo access. If another image launches Ports unprivileged, installation actions
stop with guidance; no automatic privilege escalation is attempted.

To update the updater itself, extract the next reviewed release and run
`bash install.sh` again. Logs and downloaded payloads in the new runtime remain in place; the
runtime scripts and bundled manifest are replaced. Older installations with
`data/` inside Ports are moved to `.rgbpi-updater27/legacy.*/port` as backups.
Their old logs/assets are preserved there, rather than reused automatically. For emulator/core updates,
use **UPDATE ALL RETROARCH** inside the menu. Existing complete runtimes are
not automatically refreshed from `main` on each launch.

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
UPDATE ALL RETROARCH
```

One press checks and updates only the RetroArch binary and RetroArch cores, in this order:

```text
RetroArch
Cores
```

CRT timings remain unchanged by **UPDATE ALL RETROARCH** and are available only as a separate manual operation with `./update.sh timings`. A manual CRT compatibility check is available with `./update.sh crt-check`.

Each component checks its installed version and becomes a no-op when already current. Downloads are SHA-256 checked before installation. If one part of UPDATE ALL RETROARCH fails, the failure is logged and the updater can continue safely instead of turning the operation into a full system upgrade.

## RetroArch update safety

The stable RetroArch updater replaces only:

```text
/opt/retroarch/retroarch
```

It does not intentionally replace RGB-Pi configuration, DynaRes configuration or `timings.dat`.

After installation it validates the new binary and CRT/runtime prerequisites. A failed validation is reported rather than silently treating the update as successful.

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

RetroArch replacement needs root privileges. Launch from the RGB-Pi Ports
menu, whose frontend already runs as root on the inspected OS4 Final 27 card.
SSH diagnostics work as `pi`; terminal installation needs an independently
authorized root shell. Updater27 never writes sudoers or embeds a password.

See [docs/ROOT-ACCESS.md](docs/ROOT-ACCESS.md).

## RetroArch stable policy

New RetroArch builds are promoted to the stable manifest only after compatibility checks. Physical CRT validation should cover at least:

- 240p NTSC around 59.94/60 Hz;
- 288p PAL at 50 Hz;
- NES, SNES, Mega Drive, PlayStation, arcade and N64;
- mode changes / DynaRes;
- audio synchronization;
- controller reconnect;
- game → RGB-Pi menu return.

See [docs/RELEASE-POLICY.md](docs/RELEASE-POLICY.md).
