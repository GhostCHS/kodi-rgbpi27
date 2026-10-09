# Privileges on RGB-Pi OS4 Final 27

The inspected Final 27 card starts tty1 with a root autologin. The profile
hook starts `/opt/rgbpi/autostart.sh`, which runs the RGB-Pi frontend.
The frontend's Ports launcher executes `.sh` files using `os.system`, without
dropping privileges. Updater27 uses this existing context directly.
This is observed behavior, not a vendor guarantee for every modified image.

## Recommended path

Install the updater files as `pi` with `bash install.sh`, run Scan Games,
and launch the updater from Ports. No new account, sudoers rule or reboot is
required. Do not run the installer while an update is in progress.

The launcher accepts an already authorized passwordless `sudo env bash`
context for terminal use, but does not grant it. Root processes execute scripts
directly, so restricted root sudo policies cannot break Ports launches.

## SSH diagnostics

```bash
./update.sh preflight
./update.sh crt-check
./update.sh --dump-status
```

`pi` owns `/opt/retroarch/cores` on the inspected card, so Unix permissions
permit core writes. The current updater still requires root for installation
because it also uses system log paths and dependency installation. Directory
ownership alone does not establish a rootless update implementation.

## Removed bootstrap

Previous versions piped the default SSH password into `sudo env bash` and
installed `pi ALL=(ALL) NOPASSWD:ALL`. A password cannot override command
restrictions. That flow is removed; old bootstrap helpers now stop without
writing anything. The legacy `root` command also stops. No existing sudoers
file is deleted automatically. If an earlier version granted broad sudo,
review that policy separately with your administrator.

Do not authorize scripts stored in writable ROM directories via sudoers.
A rule naming such a script grants whoever can replace it equivalent root
execution. The Ports mechanism already trusts installed scripts; review the
release before copying it onto the device.
