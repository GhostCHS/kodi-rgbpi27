# Release policy

RGB-Pi OS4 Final 27 is an appliance-style CRT distribution. "Newest" is not automatically "better" when an emulator frontend is coupled to 15-kHz timings, native video output and custom launch scripts.

## Stable channel rules

A payload can be promoted to `manifest.json` only when all of the following are true:

1. The payload is built for ARM64 against a userspace compatible with Debian Bullseye / OS4 Final 27.
2. SHA-256 hashes are recorded before release.
3. The previous payload is backed up by the installer.
4. The update passes a real Raspberry Pi 4 + RGB-Pi cable + CRT test.
5. PAL and NTSC content are tested.
6. Returning to the RGB-Pi frontend still works.
7. No kernel, firmware or distribution upgrade is required.

## Automated CRT preservation guard

Before a RetroArch payload is considered safe for the stable updater, Updater27 now checks the software-side invariants that RGB-Pi OS4 depends on:

- target system is AArch64 and the RGB-Pi UI tree is present;
- `/opt/rgbpi/ui/data/timings.dat` remains present and non-empty;
- the replacement RetroArch binary is AArch64;
- all dynamic libraries resolve;
- RetroArch reports KMS, EGL, OpenGLES, ALSA and UDEV support;
- stable manifest metadata marks the RetroArch payload as CRT-validated;
- stable `timings.dat` metadata remains explicitly tied to OS4 Final 27;
- the RetroArch updater replaces the frontend binary only and does not overwrite RGB-Pi configs or timings;
- failed post-install validation restores the previous RetroArch binary and version marker automatically.

These checks protect the CRT path from accidental generic desktop builds. They do not prove correct 15-kHz timing on physical hardware, so the real CRT regression matrix below remains mandatory before promotion.

## CRT regression matrix

At minimum test:

- 240p NTSC title around 59.94/60 Hz
- 288p PAL title at 50 Hz
- NES
- SNES
- Mega Drive / Genesis
- arcade title with non-console refresh rate
- PlayStation
- N64
- menu -> game -> menu transition
- controller disconnect/reconnect
- audio after a mode switch

For RetroArch specifically, verify that the binary still behaves correctly with the RGB-Pi native video/timing integration. A generic upstream ARM64 binary must not be promoted solely because it launches.

## Current holds

### RetroArch

Upstream stable: **1.22.2**

Validated RGB-Pi payload: **1.22.0-rgbpi1**

1.22.2 remains held until an RGB-Pi-compatible build is produced and the CRT matrix above passes.

### Kodi

Upstream stable: **21.3 Omega**

The current RGB-Pi payload is already based on Kodi 21.3 and remains the stable target.

## Base OS policy

The updater must not automatically run:

```text
apt full-upgrade
rpi-update
raspi-update
kernel package replacement
bootloader / firmware replacement
```

Individual runtime dependencies may be installed when a component explicitly requires them, but the updater should not turn OS4 into a rolling Debian system.
