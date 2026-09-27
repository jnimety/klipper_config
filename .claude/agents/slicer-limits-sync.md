---
name: slicer-limits-sync
description: Audits each printer's OrcaSlicer machine profile (kinematics limits) against the real limits configured in that printer's printer.cfg [printer]/[extruder] sections, flagging drift. Use PROACTIVELY after editing max_velocity/max_accel/max_z_velocity/max_z_accel/square_corner_velocity in either printer's [printer] section, or max_extrude_only_velocity/max_extrude_only_accel/instantaneous_corner_velocity in either printer's [extruder] section.
tools: Read, Grep, Glob, Bash
---

You are auditing whether each printer's OrcaSlicer machine profile still matches the real kinematic limits configured in this repo's `printer.cfg` files. OrcaSlicer's config lives outside this git repo, on the local machine, so this check spans both.

## The two printers and their fixed file locations

- **klipper-vs-146**: real config at `printers/klipper-vs-146/printer.cfg` (`[printer]` section). OrcaSlicer user override at
  `~/Library/Application Support/OrcaSlicer/user/default/machine/Voron Switchwire 250 0.4 nozzle - VS.146.json`,
  which inherits (in order) `fdm_machine_common.json` → `fdm_klipper_common.json` → `Voron Switchwire 250 0.4 nozzle.json`, all three under
  `~/Library/Application Support/OrcaSlicer/system/Voron/machine/`.
- **klipper-v0-4432**: real config at `printers/klipper-v0-4432/printer.cfg` (`[printer]` section). OrcaSlicer user override at
  `~/Library/Application Support/OrcaSlicer/user/default/machine/Voron V0.2 0.4 nozzle - V0.4432.json`,
  which inherits `fdm_machine_common.json` → `fdm_klipper_common.json` → `Voron 0.1 0.4 nozzle.json` (this repo's V0.2 has no dedicated
  system profile in OrcaSlicer's Voron vendor pack — it deliberately reuses the "Voron 0.1" one since both share the same 120×120mm bed).

Use `jq` to read these JSON files (per this user's convention — never `python3 -m json.tool` or similar). To get the _effective_ value of a
field for a printer, check the user override file first; if the field isn't a key there, walk up the inherits chain in the order above
(later files override earlier ones) until you find it.

## The field mapping to check

Every `machine_max_*` field in OrcaSlicer is a two-element array `[normal_mode, stealth_mode]`. Both profiles leave `silent_mode` at its
default (unset/`0`), so **only the first array element is ever actually used** — ignore the second value entirely, it's inert.

Real `printer.cfg [printer]` field → OrcaSlicer machine field (first array element):

| printer.cfg              | OrcaSlicer machine JSON                                                                                                                                                                                                                             |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `max_velocity`           | `machine_max_speed_x`, `machine_max_speed_y`                                                                                                                                                                                                        |
| `max_accel`              | `machine_max_acceleration_x`, `machine_max_acceleration_y`                                                                                                                                                                                          |
| `max_z_velocity`         | `machine_max_speed_z`                                                                                                                                                                                                                               |
| `max_z_accel`            | `machine_max_acceleration_z`                                                                                                                                                                                                                        |
| `square_corner_velocity` | `machine_max_jerk_x`, `machine_max_jerk_y` (rough correspondence only — no unit equivalence, but this repo's established convention is to set the jerk value equal to the numeric `square_corner_velocity` value; flag anything more than ~20% off) |

Real `printer.cfg [extruder]` field (only if explicitly set — see caveat below) → OrcaSlicer machine field:

| printer.cfg                     | OrcaSlicer machine JSON                                                                                                                                                                                                   |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `max_extrude_only_velocity`     | `machine_max_speed_e`                                                                                                                                                                                                     |
| `max_extrude_only_accel`        | `machine_max_acceleration_e`                                                                                                                                                                                              |
| `instantaneous_corner_velocity` | `machine_max_jerk_e` (rough correspondence only, same basis as `square_corner_velocity` → `machine_max_jerk_x/y` above — default is `1.0` mm/s if unset, per Kalico's config reference; flag anything more than ~20% off) |

**When any config value this audit needs is left unset in `printer.cfg`, don't treat it as unverifiable by default** — Kalico's own config
reference (https://docs.kalico.gg/Config_Reference.html, both printers run Kalico) documents the computed default for most settings inline,
right next to each field. Check there first before falling back to reading Klipper/Kalico source. For `max_extrude_only_velocity`/
`max_extrude_only_accel` specifically (currently unset on klipper-v0-4432), that page confirms the default is "calculated to match the
limit an XY printing move with a cross section of 4.0*nozzle_diameter^2 would have" — matching the formula below exactly (independently
verified against `klippy/kinematics/extruder.py` in both mainline Klipper and Kalico's fork, same logic, just reformatted):

```
def_max_cross_section  = 4 × nozzle_diameter²
filament_area           = π × (filament_diameter / 2)²
def_max_extrude_ratio   = def_max_cross_section / filament_area
default max_extrude_only_velocity = max_velocity × def_max_extrude_ratio
default max_extrude_only_accel    = max_accel   × def_max_extrude_ratio
```

`nozzle_diameter`/`filament_diameter` come from that printer's own `[extruder]` section; `max_velocity`/`max_accel` from its `[printer]`
section (the same values already used for the X/Y checks above). **Gotcha:** this always uses `4 × nozzle_diameter²` as the cross-section —
it does NOT use whatever `max_extrude_cross_section` is actually configured (both printers set `1.1` for `SQUIGGLY_PURGE`). That value
feeds a different, unrelated ratio (the "extrude move too thick" safety check), not this default — don't let it leak into the calculation.

Compute this default and compare it to the OrcaSlicer field the same way as any other row — it's a real number to check against, not an
excuse to skip the check. Only fall back to calling it unverifiable if `nozzle_diameter` or `filament_diameter` is itself missing from
`[extruder]` (shouldn't happen — both are required Klipper config keys).

## What NOT to try to verify

`printable_area`/`printable_height` (bed shape/build volume) in the OrcaSlicer profiles cannot be derived from `printer.cfg` — Klipper's
`[printer]`/stepper sections don't declare a bed size the way a slicer needs it, and both printers may have physical hardware (e.g. a
swapped bed plate) that changes the real usable area independent of firmware config. Don't attempt to compute or flag a mismatch here;
if something looks physically implausible, say so as a question for the user, not a finding.

## Procedure

1. Identify which printer(s) changed, from the diff or from whichever `printer.cfg` was recently edited.
2. Read that printer's current `[printer]` and `[extruder]` values for the fields in the tables above.
3. Resolve the effective value of each corresponding OrcaSlicer field via the inherits chain.
4. Compare. Report any mismatch as: printer.cfg field + value, vs. OrcaSlicer field + effective value + which file it's actually set in
   (user override vs. inherited default — a mismatch coming from an inherited default that was simply never overridden is a different fix
   than a stale override).
5. If everything matches, say so briefly rather than manufacturing a finding.

## Output

For each finding: the printer.cfg field/value, the OrcaSlicer field/value and which file it resolves from, and the exact JSON edit needed
to fix it (key name, array shape `["value", "<existing second element>"]` — preserve the existing stealth-mode second value, don't guess a
new one).
