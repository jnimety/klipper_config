# klipper_config

Klipper/Moonraker configuration for two printers, tracked in one repo.

## Layout

```
klipper_config/
├── ansible/                  # provisions a fresh Pi with prerequisites (Klipper/Moonraker/web UI/webcam/plugins) — see ansible/README.md
├── macros/                   # shared, hardware-agnostic gcode macros + client macro pack
│   ├── debug.cfg              # DUMP_PARAMETERS
│   └── mainsail.cfg           # stock Mainsail client macros (PAUSE/RESUME/CANCEL_PRINT), used by both printers
└── printers/
    ├── klipper-vs-146/        # SKR Mini E3 / corexz / BLTouch / Fluidd
    │   ├── printer.cfg
    │   ├── moonraker.conf
    │   ├── telegram.conf
    │   └── macros -> ../../macros
    └── klipper-v0/             # Voron 0.2: SKR Pico + LDO Picobilical toolhead board / corexy / sensorless XY homing / Mainsail
        ├── printer.cfg
        ├── ldo-upstream-printer.cfg  # unused vendor reference copy — not [include]'d by printer.cfg, kept for comparison against upstream
        ├── ldo-picobilical.cfg
        ├── sensorless_homing.cfg
        ├── moonraker.conf
        ├── telegram.conf
        └── macros -> ../../macros
```

Each printer directory has a `macros` symlink pointing at the top-level `macros/` directory, so a printer's `printer.cfg` can pull in shared macros with a same-directory-looking include — e.g. `[include macros/debug.cfg]` — without relying on `../` traversal through what is, on each host, itself a symlink (`~/printer_data/config`). Only files with zero hardware coupling belong in `macros/`; anything touching pins, kinematics, or printer-specific parking/heating behavior stays in the printer's own directory. `mainsail.cfg` is the one file there that isn't a pure `[gcode_macro]` set — it also carries a few generic, equally hardware-agnostic extras sections (`[virtual_sdcard]`, `[pause_resume]`, etc.). Both printers include it for `PAUSE`/`RESUME`/`CANCEL_PRINT` (it's UI-agnostic — klipper-vs-146 still uses Fluidd as its actual web UI), each with its own `printer.cfg`-level `[gcode_macro _CLIENT_VARIABLE]` customizing just what it needs. `PRINT_START`/`PRINT_END` differ enough between the two printers' hardware that they're left printer-specific.

`secrets.conf` and Moonraker/Klipper-generated backup files (`printer-*.cfg`, `.moonraker.conf.bkp`, `.fluidd*.json`) are gitignored and stay host-local — see `.gitignore`.

## Deploying to a printer

Each host gets a single clone of this repo, with `~/printer_data/config` symlinked into the printer's subdirectory (Klipper/Moonraker require `printer.cfg` at that fixed path, so the printer-specific directory has to be swapped in directly rather than the whole repo).

1. `git clone git@github.com:jnimety/klipper_config.git ~/klipper_config` (or `git -C ~/klipper_config pull` if already present).
2. Copy forward host-local gitignored files: `cp ~/printer_data/config/secrets.conf ~/klipper_config/printers/<name>/secrets.conf`.
3. `sudo systemctl stop klipper moonraker`.
4. `mv ~/printer_data/config ~/printer_data/config.bak-$(date +%Y%m%d)` (safety net — the backup/`.bkp` files inside don't need to be preserved, Klipper/Moonraker regenerate them).
5. `ln -s ~/klipper_config/printers/<hostname> ~/printer_data/config`.
6. Sanity check: `diff -rq ~/printer_data/config.bak-*/ ~/printer_data/config/` and confirm the only differences are the excluded backup/secrets files.
7. `sudo systemctl start klipper moonraker`; check `klippy.log` for config errors, load Fluidd/Mainsail, confirm the `SAVE_CONFIG` block (PID tunes, probe offset / bed mesh or endstop calibration) is intact, and do a homing test.
8. Once stable for a few days, delete the `.bak-*` directory.

Do one printer at a time — whichever isn't mid-print — with a soak period before touching the second.

## Upgrading Klipper firmware (klipper-vs-146)

klipper-vs-146 has two Klipper MCU targets sharing one `~/klipper` checkout: the main board (`[mcu]`, SKR Mini E3 v2.0 / STM32F103) and a host-side Linux process (`[mcu rpi]`, backing the `rpi:gpio12`/`13`/`18` pins and an SPI `cs_pin` in `printer.cfg`). Building one overwrites `~/klipper/.config`, so after rebuilding either target, restore the _other_ target's config too — otherwise the next plain `make` silently targets the wrong architecture.

1. `cd ~/klipper && git pull --ff-only` — the checkout also carries untracked local files (`klippy/extras/autotune_tmc.py`, `motor_constants.py`, `motor_database.cfg`, from the `klipper_tmc_autotune` moonraker-managed plugin); a plain pull doesn't touch them.
2. If `klippy-env`'s Python dependencies need a refresh (e.g. after a host OS Python version bump — `readlink -f ~/klippy-env/bin/python3` shows what it's currently pinned to): `rm -rf ~/klippy-env && virtualenv -p python3 ~/klippy-env && ~/klippy-env/bin/pip install -r ~/klipper/scripts/klippy-requirements.txt`, then `sudo systemctl restart klipper`.
3. Main MCU firmware:
   - `cp ~/klipper_config/printers/klipper-vs-146/klipper-mcu.config ~/klipper/.config && cd ~/klipper && make olddefconfig && make`
   - This board doesn't support `make flash` (no DFU bootloader) — flash via the SD-card bootloader protocol instead: `~/klipper/scripts/flash-sdcard.sh /dev/serial/by-id/usb-Klipper_stm32f103xe_37FFD6055358353215710843-if00 btt-skr-mini-e3-v2`
   - `sudo systemctl restart klipper`
4. Host Linux MCU (`[mcu rpi]`):
   - `cp ~/klipper_config/printers/klipper-vs-146/klipper-mcu-rpi.config ~/klipper/.config && cd ~/klipper && make olddefconfig && make && sudo make flash` (installs to `/usr/local/bin/klipper_mcu`, restarts `klipper-mcu.service`)
   - Restore the main MCU's config: `cp ~/klipper_config/printers/klipper-vs-146/klipper-mcu.config ~/klipper/.config && cd ~/klipper && make olddefconfig`
   - `sudo systemctl restart klipper` — restarting `klipper-mcu.service` drops Klippy's existing connection to it; Klippy doesn't reconnect on its own.
5. Verify: `curl -s http://localhost:7125/printer/info` should report `"state": "ready"` with `software_version` matching what `make` printed for both targets.

The two `.config` files above are curated, not raw menuconfig dumps — `make olddefconfig` resolves the rest of each target's Kconfig tree deterministically. One gotcha worth remembering: `CONFIG_MACH_STM32F103=y` alone isn't enough to select the STM32 architecture — menuconfig's top-level "Micro-controller Architecture" choice also needs `CONFIG_MACH_STM32=y` set first, or `olddefconfig` silently falls back to the first choice (AVR) instead of erroring.

## Upgrading Klipper firmware (klipper-v0)

klipper-v0 has three Klipper MCU targets sharing one `~/klipper` checkout: the main board (`[mcu]`, SKR Pico / RP2040), the LDO Picobilical toolhead board (`[mcu umb]`, also RP2040 — same chip, same firmware build, only the flash target differs), and a host-side Linux process (`[mcu rpi]`, backing the ADXL345 accelerometer wired directly to the Pi's SPI/GPIO header — see `ldo-picobilical.cfg`). As with klipper-vs-146, building one target overwrites `~/klipper/.config`, so after rebuilding the Linux target, restore the RP2040 config too, or the next plain `make` silently targets the wrong architecture.

1. `cd ~/klipper && git pull --ff-only` — the checkout also carries untracked local files (`klippy/extras/autotune_tmc.py`, `motor_constants.py`, `motor_database.cfg`, from the `klipper_tmc_autotune` moonraker-managed plugin); a plain pull doesn't touch them.
2. If `klippy-env`'s Python dependencies need a refresh (e.g. after a host OS Python version bump — `readlink -f ~/klippy-env/bin/python3` shows what it's currently pinned to): `rm -rf ~/klippy-env && virtualenv -p python3 ~/klippy-env && ~/klippy-env/bin/pip install -r ~/klipper/scripts/klippy-requirements.txt`, then `sudo systemctl restart klipper`.
3. RP2040 firmware (same build serves both the main board and the toolhead — no need to rebuild between flashing each one):
   - `cp ~/klipper_config/printers/klipper-v0/klipper-mcu-rp2040.config ~/klipper/.config && cd ~/klipper && make olddefconfig && make`
   - RP2040's built-in USB bootloader means `make flash` works directly — no SD-card dance needed. Flash the main board: `make flash FLASH_DEVICE=/dev/serial/by-id/usb-Klipper_rp2040_4550357129103DF8-if00`
   - Flash the toolhead board: `make flash FLASH_DEVICE=/dev/serial/by-id/usb-Klipper_rp2040_48313136300E9E7A-if00`
   - `sudo systemctl restart klipper`
4. Host Linux MCU (`[mcu rpi]`):
   - `cp ~/klipper_config/printers/klipper-v0/klipper-mcu-rpi.config ~/klipper/.config && cd ~/klipper && make olddefconfig && make && sudo make flash` (installs to `/usr/local/bin/klipper_mcu`, restarts `klipper-mcu.service`)
   - Restore the RP2040 config: `cp ~/klipper_config/printers/klipper-v0/klipper-mcu-rp2040.config ~/klipper/.config && cd ~/klipper && make olddefconfig`
   - `sudo systemctl restart klipper` — restarting `klipper-mcu.service` drops Klippy's existing connection to it; Klippy doesn't reconnect on its own.
5. Verify: `curl -s http://localhost:7125/printer/info` should report `"state": "ready"` with `software_version` matching what `make` printed for both targets. Per LDO's guide, the ADXL345 FFC cable should stay unplugged except when actually running `ACCELEROMETER_QUERY`/`SHAPER_CALIBRATE` — Klipper reaches "ready" fine either way, since the `adxl345` module only probes the chip when a measurement starts.

Unlike klipper-vs-146's STM32 board, RP2040 doesn't need a bootloader-offset/clock-crystal choice — the two `.config` files above were verified to resolve byte-identically to the configs that built the firmware currently running on both RP2040 boards.
