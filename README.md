# klipper_config

Klipper/Moonraker configuration for two printers, tracked in one repo.

## Layout

```
klipper_config/
├── macros/                   # shared, hardware-agnostic gcode macros
│   └── debug.cfg              # DUMP_PARAMETERS
└── printers/
    ├── klipper-vs-146/        # SKR Mini E3 / corexz / BLTouch / Fluidd
    │   ├── printer.cfg
    │   ├── moonraker.conf
    │   ├── telegram.conf
    │   ├── client.cfg          # stock Fluidd client config
    │   ├── client_macros.cfg   # stock Fluidd client macros
    │   └── macros -> ../../macros
    └── klipper-v0/             # Voron 0.2: SKR Pico + LDO Picobilical toolhead board / corexy / sensorless XY homing / Mainsail
        ├── printer.cfg
        ├── ldo-upstream-printer.cfg  # unused vendor reference copy — not [include]'d by printer.cfg, kept for comparison against upstream
        ├── ldo-picobilical.cfg
        ├── homing.cfg
        ├── a-better-print-start-macro.cfg
        ├── mainsail.cfg         # stock Mainsail client macros
        ├── moonraker.conf
        ├── telegram.conf
        └── macros -> ../../macros
```

Each printer directory has a `macros` symlink pointing at the top-level `macros/` directory, so a printer's `printer.cfg` can pull in shared macros with a same-directory-looking include — e.g. `[include macros/debug.cfg]` — without relying on `../` traversal through what is, on each host, itself a symlink (`~/printer_data/config`). Only macros with zero hardware coupling belong in `macros/`; anything touching pins, kinematics, or printer-specific parking/heating behavior stays in the printer's own directory. `PAUSE`/`RESUME`/`CANCEL_PRINT`/`PRINT_START`/`PRINT_END` currently differ enough between the two printers (different UI flavors — Fluidd vs. Mainsail client macros — and different hardware) that they're left printer-specific; convergence is a possible future cleanup, not done here.

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
