# Root access on RGB-Pi OS4 Final 27

User and password changes are intentionally **out of scope for the current hardware-test phase**.

Stock RGB-Pi OS4 Final 27 can restrict the `pi` account to a very small sudo allow-list. On the current test system, non-interactive full sudo is not available.

## What works without root

The following Updater27 actions are designed to work as the normal OS4 user:

```bash
./update.sh preflight
./update.sh crt-check
./update.sh baseline
./update.sh --dump-status
```

These actions inspect the installation, verify CRT-related prerequisites, record the current state, and report available updates. They do not replace emulator binaries, cores, timings, kernel or firmware.

## What still requires root

Actual installation actions remain privileged:

```bash
./update.sh kodi --update
./update.sh retroarch --update
./update.sh cores --update
./update.sh timings --update
```

Updater27 does not attempt to bypass OS4's sudo policy and does not install a global `NOPASSWD:ALL` rule.

## Why account changes are deferred

RGB-Pi OS4 is an appliance-style distribution. Renaming the stock user or changing its privilege model can affect launch scripts, Kodi data paths, services, controller setup or other assumptions outside the updater.

For the first real-hardware validation, the safer approach is to leave the stock account and sudo configuration untouched and test all rootless diagnostics first.
