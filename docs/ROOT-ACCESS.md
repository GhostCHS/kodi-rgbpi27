# Maintenance account and root access on RGB-Pi OS4 Final 27

## Preferred account

RGB-Pi Updater27 uses the following maintenance account convention:

```text
username: admin
initial password: admin
```

Change the initial password after the first login:

```bash
passwd
```

The updater deliberately leaves the original RGB-Pi OS4 account in place. Renaming or deleting that account could break OS4 services, launch scripts, Kodi data paths or other software that still assumes the stock account exists.

## Create the admin account

From a root-capable shell:

```bash
sudo bash "/roms/ports/RGB-PI Updater27/update.sh" setup-admin
```

The setup script creates `admin` with `/home/admin` when needed, sets the initial password only for a newly created account, adds available Raspberry Pi hardware-access groups, and installs a normal password-protected sudo rule. It does not install `NOPASSWD:ALL` and does not remove or rename the original OS4 account.

If `admin` already exists, its password is left unchanged. To intentionally reset it to the project default:

```bash
sudo bash "/roms/ports/RGB-PI Updater27/data/setup_admin_user.sh" --reset-password
```

Change that temporary/default password immediately afterward.

## Normal SSH maintenance

After the account exists:

```text
ssh admin@<rgbpi-ip>
password: admin
```

Then change the password:

```bash
passwd
```

Update actions can be run with normal password-protected sudo:

```bash
sudo bash "/roms/ports/RGB-PI Updater27/update.sh" preflight
sudo bash "/roms/ports/RGB-PI Updater27/update.sh" crt-check
sudo bash "/roms/ports/RGB-PI Updater27/update.sh" kodi --update
sudo bash "/roms/ports/RGB-PI Updater27/update.sh" retroarch --update
sudo bash "/roms/ports/RGB-PI Updater27/update.sh" cores --update
sudo bash "/roms/ports/RGB-PI Updater27/update.sh" timings --update
```

## Ports-menu privilege note

The framebuffer menu cannot reliably prompt for a sudo password. Therefore status, Preflight and CRT checks work without root, while privileged update actions require either launching the updater itself from an already privileged context or using the SSH commands above.

Updater27 intentionally does not weaken the machine with a global passwordless sudo rule just to make the menu able to elevate itself.

## Why the stock account remains

RGB-Pi OS4 Final 27 is an appliance-style distribution. Some stock scripts and user data can still reference the original account. The preferred human maintenance account is `admin`, but compatibility takes priority over renaming internal OS identities.
