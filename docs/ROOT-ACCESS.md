# Root access on RGB-Pi OS4 Final 27

Updater27 now follows the upstream RGB-Pi updater's first-run privilege setup for the stock `pi` account. A reboot is requested after that initial setup so future updater launches can run non-interactively.

## What works without root

The following Updater27 actions are designed to work as the normal OS4 user:

```bash
./update.sh preflight
./update.sh crt-check
./update.sh --dump-status
```

These actions inspect the installation and verify CRT-related prerequisites without replacing emulator binaries, cores, timings, kernel or firmware.

## What still requires root

Actual installation actions remain privileged:

```bash
./update.sh kodi --update
./update.sh retroarch --update
./update.sh cores --update
./update.sh timings --update
```

For update execution, Updater27 uses the same first-run privilege model as the upstream RGB-Pi updater.

## Account policy

The stock `pi` account is kept in place. Updater27 does not create or migrate to a separate maintenance user.
