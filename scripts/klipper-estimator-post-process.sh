#!/bin/bash
# OrcaSlicer post-processing script: rewrite print time estimates with klipper_estimator.
# Usage: klipper-estimator-post-process.sh <printer hostname> <gcode file>   (Orca appends the gcode path)
# Uses the printer's live config via Moonraker, falling back to the last cached copy when the printer is off.
# With no cache yet and the printer off, leaves the gcode untouched (Orca's own estimate stays).
set -uo pipefail
host=$1
gcode=$2
cache_dir=$HOME/.cache/klipper_estimator
cache=$cache_dir/$host.json
mkdir -p "$cache_dir" # klipper_estimator won't create it, and only warns if the cache write fails

estimator=("$HOME/workspace/klipper_estimator/target/release/klipper_estimator"
  --config_moonraker_url "https://$host.local:7130" --config_moonraker_cache_file "$cache")

if [[ -f $cache ]]; then
  exec "${estimator[@]}" --config_moonraker_ignore_error post-process "$gcode"
fi
# No cache: --config_moonraker_ignore_error would fail anyway (it parses an empty config), so skip on error instead.
"${estimator[@]}" post-process "$gcode" || echo "klipper_estimator: no config for $host (offline, no cache); skipping" >&2
exit 0
