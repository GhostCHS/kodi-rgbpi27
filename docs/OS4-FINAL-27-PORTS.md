# RGB-Pi OS4 Final 27: ports installation findings

This note records the reusable findings from inspecting an OS4 Final 27 SD card on 9 October 2026. The inspected card already contained third-party changes, so treat the privilege and ownership details as observed OS4 behavior, not a guarantee for every modified image.

## Why Ports can install system files

The inspected image autologs tty1 in as `root` through the getty drop-in. `/etc/profile.d/10-rgbpi.sh` starts `/opt/rgbpi/autostart.sh` for root on tty1. The RGB-Pi frontend handles `.sh` entries from its Ports system by invoking the selected path through `os.system`; it does not drop privileges in that launch path. Therefore a Port launched from the frontend already has root. A Ports updater can run privileged work directly and does not need to grant SSH user `pi` general sudo rights.

This is a property of the inspected image, not a documented promise that every OS4-derived image launches Ports as root. Updater27 checks for root or already-authorized noninteractive sudo and exits with guidance if neither is available. It does not install sudoers rules or embed a password.

## Paths and permissions observed

The image reports Debian 11 Bullseye and RGB-Pi UI version 4.27, date version `20240101`. The storage tree is on the root filesystem under `/media/sd`, with ROMs under `/media/sd/roms` and the Ports index at `/media/sd/dats/games.dat`.

| Path | Observed mode and owner | Consequence |
|---|---|---|
| `/opt/retroarch` | `0755`, root:root | `pi` cannot replace the RetroArch binary or parent-owned version marker. |
| `/opt/retroarch/retroarch` | `0755`, root:root | Binary replacement needs root. |
| `/opt/retroarch/cores` | `0755`, UID/GID 1000 | Directory entries are writable by `pi`; individual core files have mixed ownership. |
| `/opt/rgbpi` | `0755`, root:root | System application tree is root-owned. |
| `/opt/rgbpi/ui` | `0777`, root:root | Writable by `pi` through directory permissions. |
| `/opt/rgbpi/ui/data` | `0777`, root:root | Writable by `pi` through directory permissions. |
| `/media/sd` | `0777`, root:group 1000 | ROM storage is writable by the normal account. |
| `/media/sd/roms/ports` | `0777`, UID/GID 1000 | A normal account can install a Port. |

`timings.dat`, `cores.cfg` and `systems.dat` were mode `0666`; `retroarch.cfg` was `0644` and root-owned. The updater leaves timings and configuration untouched. The `cores` directory ownership alone does not make the existing core updater rootless: that updater also needs root-owned system logs, may install missing tools and validates/installations as root.

The sudoers directory contained `010_at-export`, `010_proxy`, `020_kodi`, and a README, with no `010_pi-nopasswd`. `020_kodi` grants video-group users only the listed virtual-terminal commands. The root-owned main sudoers file and restrictive drop-ins could not be read without interactive administrator authentication, so the complete effective sudo policy was not established.

## Ports layout

The RGB-Pi scanner reads `games.dat` and scans files with the `.sh` extension in `roms/ports`. Keeping every updater helper in that directory causes the scanner to expose helpers such as the timings updater and sudo bootstrap as individual Ports. Updater27 now stores its runtime outside the ROM scan tree at `<storage>/.rgbpi-updater27` and leaves a single wrapper at `roms/ports/RGB-PI Updater27/update.sh`.

The installer moves an existing Updater27 folder with an unrecognized old layout to `<storage>/.rgbpi-updater27/legacy.*/port`, preserving the previous files. It then removes only stale `games.dat` rows referring to `/roms/ports/RGB-PI Updater27/data/`, after saving the original file as `.rgbpi-updater27/games.dat.before-updater27-cleanup`. The updater launch row remains. Other games and Ports are preserved.

## Scope boundaries

OS4 also has a profile-hook startup path, an `rc.local`, a system-update mechanism, and a `rgbpiui.service` unit. None is needed to install Updater27. The service unit found in the image referenced a missing startup script and had no active unit link; the configured tty1 profile hook was the relevant startup path.

Updater27 does not edit sudoers, startup scripts, `games.dat` beyond removing its own stale helper rows, kernel, firmware, boot settings, RetroArch configuration or CRT timings. Stable RetroArch and core updates retain the project's manifest and checksum checks. Software checks do not replace a physical CRT validation.
