# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This is a personal [Klipper](https://www.klipper3d.org/) 3D printer configuration repo for two printers, not a software project. There is no build, lint, or test tooling — changes are validated by restarting Klipper/Moonraker on the printer's host and observing behavior, or by careful manual review of G-code macro logic. There are no automated tests to run.

## Layout

- `printers/klipper-vs-146/` — SKR Mini E3, corexz kinematics, BLTouch probe, Fluidd UI.
- `printers/klipper-v0/` — Voron 0.2 (SKR Pico + LDO Picobilical toolhead board), corexy kinematics, sensorless XY homing, Mainsail UI.
- `macros/` — shared, hardware-agnostic gcode macros (`debug.cfg` / `DUMP_PARAMETERS`, `prime_line.cfg` / `PRIME_LINE`). Each printer directory has a `macros` symlink to this directory, included as `[include macros/<file>.cfg]`. Only add macros here that have zero hardware coupling (no pin references, no printer-specific parking/heating values) — everything else belongs in the printer's own directory. The two printers' `PAUSE`/`RESUME`/`CANCEL_PRINT`/print-start/print-end macros are intentionally _not_ unified: they differ in UI flavor (Fluidd vs. Mainsail client macros) and hardware, so each stays local to its printer.
- Each printer's own `printer.cfg`, `moonraker.conf`, `telegram.conf` follow the same per-file conventions described below.

See `README.md` for the full directory tree and the deployment runbook (each host clones this repo to `~/klipper_config` and symlinks `~/printer_data/config` to `~/klipper_config/printers/<hostname>`).

## Per-printer files

- `printer.cfg` — main Klipper config: MCU pin mappings, steppers/TMC2209 drivers (klipper-vs-146 also uses `[autotune_tmc]` per stepper), bed mesh, probe, extruder/heater, input shaper, and custom `[gcode_macro]` definitions (print start/end, pause/resume, filament load/unload, bed leveling helpers). Also contains the `SAVE_CONFIG` auto-generated block at the bottom (PID tunes, bed mesh calibration, probe/endstop offsets) — never hand-edit below the `#*# <---------------------- SAVE_CONFIG ---------------------->` marker; Klipper rewrites it. This block is independent per printer.
- `client.cfg` / `client_macros.cfg` (klipper-vs-146 only) — stock Fluidd-required includes (virtual_sdcard, pause/resume, display_status, base `CANCEL_PRINT`/`PAUSE`/`RESUME` macros). `printer.cfg` overrides `PAUSE`/`RESUME`/`CANCEL_PRINT` again after including `client_macros.cfg`, chaining through `rename_existing` (`PAUSE_BASE`/`RESUME_BASE`) — the effective macro is the one defined later in `printer.cfg`. Keep any macro edits consistent with this chaining pattern.
- `mainsail.cfg` (klipper-v0 only) — stock Mainsail-required client macros (the Alex Zellner `_CLIENT_VARIABLE`-based `PAUSE`/`RESUME`/`CANCEL_PRINT`, more feature-rich than klipper-vs-146's: runout-sensor awareness, idle-timeout restore, temp restore). Included first in `printer.cfg`; do not hand-edit, it's a vendored file.
- `ldo-upstream-printer.cfg` (klipper-v0 only) — the original LDO/Voron installer's full printer template. **Not** referenced by any `[include]` in `printer.cfg` — `printer.cfg` was customized directly instead. Kept only as a reference to diff against upstream; don't assume it reflects live config.
- `moonraker.conf` — Moonraker API server config: CORS/trusted clients, update_manager entries (moonraker-telegram-bot on both; `klipper_tmc_autotune` on both as well). klipper-v0's Moonraker auto-discovers SSL certs at `~/printer_data/certs/moonraker.{cert,key}` (a directory outside this repo) — no explicit `ssl_certificate_path` config needed for that.
- `telegram.conf` — moonraker-telegram-bot config; points at a `secrets.conf` (gitignored, lives on the printer host) for credentials.

## Secrets

Credentials (`secrets.conf`, Moonraker/Fluidd local state, printer host backups like `printer-*.cfg` and `.moonraker.conf.bkp`) are gitignored and kept out of version control — see `.gitignore` (patterns are unanchored, so they match under `printers/*/` too). Never add secrets back into tracked files; reference them via the existing `[secrets]` indirection pattern in `telegram.conf` instead.
