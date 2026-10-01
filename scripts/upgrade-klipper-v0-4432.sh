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
# USB id of an RP2040 sitting in its ROM (BOOTSEL) bootloader.
ROM_BOOTLOADER=2e8a:0003

bootloader_count() { lsusb -d "$ROM_BOOTLOADER" 2>/dev/null | grep -c . || true; }

wait_for() {
  local tries=$1 i
  shift
  for ((i = 0; i < tries; i++)); do
    "$@" && return 0
    sleep 1
  done
  return 1
}

require_rp2040() {
  if [[ ! -e $1 ]] && (($(bootloader_count) > 0)); then
    die "$1 missing but an RP2040 is in its bootloader; recover with: make -C $KLIPPER_DIR flash FLASH_DEVICE=$ROM_BOOTLOADER"
  fi
  require_device "$1"
}

# flash_usb.py's picoboot path races the USB re-enumeration after it requests
# the bootloader (FileNotFoundError on .../busnum), stranding the board in
# BOOTSEL; finish the flash from there via the ROM bootloader's USB id.
flash_rp2040() {
  local serial=$1 label=$2
  log "Flashing $label"
  if ! make -C "$KLIPPER_DIR" flash FLASH_DEVICE="$serial"; then
    log "Serial flash of $label failed; retrying via ROM bootloader ($ROM_BOOTLOADER)"
    wait_for 10 test "$(bootloader_count)" -gt 0 || die "$label not found in ROM bootloader"
    (($(bootloader_count) == 1)) || die "more than one RP2040 in ROM bootloader; flash manually"
    make -C "$KLIPPER_DIR" flash FLASH_DEVICE="$ROM_BOOTLOADER"
  fi
  wait_for 15 test -e "$serial" || die "$label didn't come back at $serial after flashing"
}

preflight_targets() {
  require_cmd lsusb
  require_file "$RPI_CONFIG"
  require_rp2040 "$MAIN_SERIAL"
  require_rp2040 "$UMB_SERIAL"
}

flash_targets() {
  build "$DEFAULT_CONFIG"
  flash_rp2040 "$MAIN_SERIAL" "main MCU (SKR Pico)"
  flash_rp2040 "$UMB_SERIAL" "toolhead MCU (mcu umb)"

  flash_host_mcu "$RPI_CONFIG"
}

upgrade_klipper "$@"
