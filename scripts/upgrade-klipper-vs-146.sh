#!/bin/bash
# Pull ~/klipper and rebuild/reflash every Klipper MCU on klipper-vs-146.
# Usage: upgrade-klipper-vs-146.sh [-y]   (-y skips the confirmation prompt)
PRINTER=klipper-vs-146
# shellcheck source=lib/upgrade-klipper.sh
source "$(dirname "$(readlink -f "$0")")/lib/upgrade-klipper.sh"

DEFAULT_CONFIG=$CONFIG_DIR/klipper-mcu.config
RPI_CONFIG=$CONFIG_DIR/klipper-mcu-rpi.config
EBB_CONFIG=$CONFIG_DIR/klipper-mcu-ebb.config
MAIN_SERIAL=/dev/serial/by-id/usb-Klipper_stm32f103xe_37FFD6055358353215710843-if00
MAIN_BOARD=btt-skr-mini-e3-v2
EBB_UUID=7deac5a898dd
KATAPULT_FLASHTOOL=$HOME/katapult/scripts/flashtool.py
# Klipper-firmware MCUs to version-check (cartographer runs its own firmware).
MCUS=(mcu "mcu rpi" "mcu EBBCan")

preflight_targets() {
  require_cmd python3
  require_file "$RPI_CONFIG"
  require_file "$EBB_CONFIG"
  require_file "$KATAPULT_FLASHTOOL"
  require_device "$MAIN_SERIAL"
  require_can_up can0
}

flash_targets() {
  build "$DEFAULT_CONFIG"
  log "Flashing main MCU (SD-card bootloader)"
  (cd "$KLIPPER_DIR" && ./scripts/flash-sdcard.sh "$MAIN_SERIAL" "$MAIN_BOARD")

  flash_host_mcu "$RPI_CONFIG"

  build "$EBB_CONFIG"
  log "Flashing EBBCan over CAN"
  python3 "$KATAPULT_FLASHTOOL" -i can0 -u "$EBB_UUID" -f "$KLIPPER_DIR/out/klipper.bin"
}

upgrade_klipper "$@"
