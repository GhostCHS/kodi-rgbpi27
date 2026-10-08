# RGB-Pi 27 Updater

A maintained fork of `joeblack2k/kodi-rgbpi` for **RGB-Pi OS4 Final 27** on Raspberry Pi 4 / Pi 400.

The goal is not to turn OS4 into a rolling Debian installation. RGB-Pi depends on a tightly coupled CRT/DPI video stack, so this updater modernizes user-space components while deliberately leaving the OS4 kernel, firmware and base distribution alone.

## Current policy

**Stable = current enough, but CRT-tested first.**

As of 2026-10-08:

| Component | Upstream stable | RGB-Pi 27 stable channel |
|---|---:|---:|
| Kodi | 21.3 Omega | 21.3 RGB-Pi build |
| RetroArch | 1.22.2 | 1.22.0-rgbpi1 until 1.22.2 passes CRT validation |
| Cores | rolling | validated bundle |
| timings.dat | RGB-Pi-specific | validated OS4 bundle |

The manifest records both the validated package and known upstream version. A newer upstream number is **not** promoted automatically if it could break 15-kHz output, DynaRes, controller input or OS4 launch integration.

## What this fork changes

- Targets this repository (`GhostCHS/kodi-rgbpi27`) for runtime updates.
- Adds an OS4 / architecture / Raspberry Pi preflight check.
- Allows version/status checks without root.
- Removes the old automatic password guessing.
- Removes automatic creation of `pi ALL=(ALL) NOPASSWD:ALL`.
- Validates the manifest before using it.
- Keeps SHA-256 validation for downloadable payloads.
- Keeps timestamped rollback backups before component replacement.
- Explicitly refuses to manage the OS4 kernel, Raspberry Pi firmware or a full distribution upgrade.

## Components

The updater manages only:

- Kodi
- Kodi joystick addon
- RetroArch frontend
- managed libretro core bundle
- RGB-Pi `timings.dat`

It intentionally does **not** run:

```text
apt full-upgrade
rpi-update
firmware upgrades
kernel replacement
```

## Installation

Place the updater in the global RGB-Pi ROMs/Ports directory:

```bash
mkdir -p "/roms/ports/RGB-PI Updater"

curl -fsSL \
  "https://raw.githubusercontent.com/GhostCHS/kodi-rgbpi27/main/update.sh" \
  -o "/roms/ports/RGB-PI Updater/update.sh"

chmod +x "/roms/ports/RGB-PI Updater/update.sh"
```

Then rescan games in the RGB-Pi UI and launch it from **Ports**. The updater is location-independent internally; `/roms/ports/RGB-PI Updater` is the canonical installation path.

The minimal launcher downloads the current text runtime from this repository on first start.

## Preflight

From SSH:

```bash
"/roms/ports/RGB-PI Updater/update.sh" preflight
```

Typical Final 27 output should show:

```text
ARCH=aarch64
RGBPI_UI=YES
RETROARCH=YES
TIMINGS=YES
```

The primary tested target is Raspberry Pi 4 / Pi 400 running the Bullseye-based RGB-Pi OS4 Final 27 image.

## Root access

Reading status does not require root. Installing Kodi, RetroArch, cores or timings does.

RGB-Pi OS4 Final 27 can intentionally ship the `pi` account with a very restricted sudo policy. This fork does not silently weaken that policy.

See [docs/ROOT-ACCESS.md](docs/ROOT-ACCESS.md) before enabling update privileges.

## Command line

```bash
./update.sh
./update.sh preflight
./update.sh --dump-status

./update.sh kodi --status
./update.sh retroarch --status
./update.sh cores --status
./update.sh timings --status

./update.sh kodi --update
./update.sh retroarch --update
./update.sh cores --update
./update.sh timings --update
```

Update actions require working root privileges.

## RetroArch 1.22.2

RetroArch 1.22.2 is the current upstream stable version, but a generic Linux ARM64 binary is **not** automatically safe for RGB-Pi OS4. The RGB-Pi frontend, native video driver and CRT timing behavior must be validated on real 15-kHz hardware.

For that reason the stable manifest currently keeps the known RGB-Pi build until the 1.22.2 build has been tested for:

- 240p / 288p mode generation
- PAL 50 Hz and NTSC ~60 Hz
- DynaRes / per-game timing changes
- menu return and launch scripts
- audio synchronization
- controller hotplug
- representative NES, SNES, Mega Drive, PS1, arcade and N64 titles

See [docs/RELEASE-POLICY.md](docs/RELEASE-POLICY.md).

A reproducible ARM64/Bullseye **experimental 1.22.2 build workflow** is available in GitHub Actions. It is deliberately not wired into the stable manifest until real CRT testing passes. See [docs/RETROARCH-EXPERIMENTAL.md](docs/RETROARCH-EXPERIMENTAL.md).

## Rollback

The component scripts create backups below:

```text
/opt/backups/agents/kodi/
/opt/backups/agents/retroarch/
/opt/backups/agents/retroarch-cores/
/opt/backups/agents/timings/
```

A failed validation should leave the previous component recoverable from these directories.

## RGBPi-Extra

This updater and RGBPi-Extra are separate projects.

RGBPi-Extra is useful for extra systems, additional cores and OS4 tweaks. RGB-Pi 27 Updater is intended to maintain the small base stack above. Avoid letting two tools replace the same core bundle without keeping a backup.

## Status

This fork is experimental until the modernization branch has been tested on a real RGB-Pi OS4 Final 27 installation and CRT.
