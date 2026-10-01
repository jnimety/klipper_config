#!/bin/bash

sudo systemctl stop klipper

cd ~/klipper || exit
git pull --no-ff

# Upgrade mcu
cp ~/klipper_config/printers/klipper-vs-146/klipper-mcu.config ~/klipper/.config &&
  make clean &&
  make olddefconfig &&
  make &&
  ./scripts/flash-sdcard.sh /dev/serial/by-id/usb-Klipper_stm32f103xe_37FFD6055358353215710843-if00 btt-skr-mini-e3-v2

# Upgrade mcu rpi
cp ~/klipper_config/printers/klipper-vs-146/klipper-mcu-rpi.config ~/klipper/.config &&
  make clean &&
  make olddefconfig &&
  make &&
  sudo make flash

# Upgrade mcu EBBCan
cp ~/klipper_config/printers/klipper-vs-146/klipper-mcu-ebb.config ~/klipper/.config &&
  make clean &&
  make olddefconfig &&
  make &&
  ~/katapult/scripts/flashtool.py --uuid 7deac5a898dd

# Restore mcu config
cp ~/klipper_config/printers/klipper-vs-146/klipper-mcu.config ~/klipper/.config &&
  make clean

sudo systemctl start klipper
