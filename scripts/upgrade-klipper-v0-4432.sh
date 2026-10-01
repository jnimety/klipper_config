#!/bin/bash
# Pull ~/klipper and rebuild/reflash every Klipper MCU on klipper-v0-4432.
# Usage: upgrade-klipper-v0-4432.sh [-y]   (-y skips the confirmation prompt)
PRINTER=klipper-v0-4432
# shellcheck source=lib/upgrade-klipper.sh
source "$(dirname "$(readlink -f "$0")")/lib/upgrade-klipper.sh"

# SKR Pico and Picobilical toolhead share one RP2040 build.
DEFAULT_CONFIG=$CONFIG_DIR/klipper-mcu-rp2040.config
RPI_CONFIG=$CONFIG_DIR/klipper-mcu-rpi.config
MAIN_SERIAL=/dev/serial/by-id/usb-Klipper_rp2040_4550357129103DF8-if00
UMB_SERIAL=/dev/serial/by-id/usb-Klipper_rp2040_48313136300E9E7A-if00
MCUS=(mcu "mcu umb" "mcu rpi")

preflight_targets() {
  require_file "$RPI_CONFIG"
  require_device "$MAIN_SERIAL"
  require_device "$UMB_SERIAL"
}

flash_targets() {
  build "$DEFAULT_CONFIG"
  log "Flashing main MCU (SKR Pico)"
  make -C "$KLIPPER_DIR" flash FLASH_DEVICE="$MAIN_SERIAL"
  log "Flashing toolhead MCU (mcu umb)"
  make -C "$KLIPPER_DIR" flash FLASH_DEVICE="$UMB_SERIAL"

  flash_host_mcu "$RPI_CONFIG"
}

upgrade_klipper "$@"
