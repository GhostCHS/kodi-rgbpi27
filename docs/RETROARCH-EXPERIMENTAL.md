# Experimental RetroArch 1.22.2 build

The stable updater intentionally does not replace the validated RGB-Pi RetroArch payload with a generic upstream build.

This repository includes a manual GitHub Actions workflow named **Build experimental RetroArch**. It builds current RetroArch source natively on an ARM64 GitHub runner inside a Debian Bullseye container so the resulting binary targets a userspace close to RGB-Pi OS4 Final 27.

## Build profile

The workflow uses the Raspberry Pi 4 KMS/EGL/OpenGL ES configuration recommended by Libretro as a baseline:

- ARM64
- Debian Bullseye build userspace
- Cortex-A72 optimization
- KMS
- EGL
- OpenGL ES / GLES 3 / GLES 3.1
- ALSA
- udev
- X11 disabled
- Wayland disabled
- Vulkan disabled

Vulkan is intentionally disabled for this experiment because the goal is the OS4 CRT path, not a desktop/Vulkan build.

## Important limitation

This is still an **upstream RetroArch build**, not proof that it reproduces every RGB-Pi-specific behavior.

Do not put it into the stable manifest until it has passed the CRT test matrix in `RELEASE-POLICY.md`.

## Running the workflow

On GitHub:

1. Open **Actions**.
2. Open **Build experimental RetroArch**.
3. Choose **Run workflow**.
4. Keep version `1.22.2` unless intentionally testing another tag.

The workflow produces an artifact containing:

```text
retroarch-rgbpi-1.22.2-experimental.tar.gz
retroarch-rgbpi-1.22.2-experimental.tar.gz.sha256
retroarch-1.22.2-binary.sha256
BUILDINFO.txt
FEATURES.txt
LDD.txt
```

## Test procedure

Use a spare SD card or make a complete image backup first.

Back up the existing binary:

```bash
sudo cp -a /opt/retroarch/retroarch /opt/retroarch/retroarch.rgbpi27-backup
```

Extract the experimental archive somewhere temporary and replace only the frontend binary:

```bash
sudo install -m 0755 retroarch/retroarch /opt/retroarch/retroarch
```

Do **not** replace cores, configs, `timings.dat`, kernel or firmware for this test.

Then run the complete CRT regression matrix from `docs/RELEASE-POLICY.md`.

Rollback:

```bash
sudo cp -a /opt/retroarch/retroarch.rgbpi27-backup /opt/retroarch/retroarch
```
