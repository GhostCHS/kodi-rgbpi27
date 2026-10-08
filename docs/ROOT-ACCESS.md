# Root access on RGB-Pi OS4 Final 27

RGB-Pi OS4 may intentionally restrict the `pi` account. On a stock Final 27 install, `sudo -l` can show only a small allow-list such as `fgconsole` and `chvt`.

The updater does **not** try to bypass that policy.

## Recommended: standard password-protected sudo

If you want to maintain the appliance yourself, add a normal sudo rule from another Linux system while the RGB-Pi SD card is mounted.

On the RGB-Pi root filesystem create:

```text
/etc/sudoers.d/020_pi-standard
```

with:

```text
pi ALL=(ALL) ALL
```

and permissions:

```text
0440
```

Validate the file with `visudo -cf` when possible.

This keeps privilege escalation password-protected instead of granting permanent unrestricted passwordless root.

After booting RGB-Pi again, update actions can be started from SSH with:

```bash
sudo bash "/media/sd/roms/ports/RGB-PI 27 Updater/update.sh" preflight
sudo bash "/media/sd/roms/ports/RGB-PI 27 Updater/update.sh" kodi --update
sudo bash "/media/sd/roms/ports/RGB-PI 27 Updater/update.sh" retroarch --update
sudo bash "/media/sd/roms/ports/RGB-PI 27 Updater/update.sh" cores --update
sudo bash "/media/sd/roms/ports/RGB-PI 27 Updater/update.sh" timings --update
```

## Ports-menu updates

The graphical Ports launcher uses non-interactive sudo for update actions because entering a sudo password inside a 320x240 framebuffer UI is unreliable.

If `sudo -n true` fails, the GUI remains usable for status and preflight checks but will refuse installation actions.

A future release may ship a root-owned, narrowly scoped helper for graphical updates. Until that helper is audited, this fork deliberately does not write `NOPASSWD:ALL` automatically.

## Legacy unrestricted rule

The upstream project used:

```text
pi ALL=(ALL) NOPASSWD:ALL
```

That works, but it gives every process running as `pi` unrestricted root access. This fork does not install that rule.

If you deliberately choose it on a dedicated appliance, do so manually and understand the security trade-off.

## Reverting

Remove the custom sudoers file from the RGB-Pi root filesystem and reboot.

Never edit `/etc/sudoers` directly with a normal text editor unless you have a recovery path. Prefer a file in `/etc/sudoers.d/`.
