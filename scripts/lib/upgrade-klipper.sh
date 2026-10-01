# shellcheck shell=bash
# Shared logic for scripts/upgrade-klipper-<printer>.sh -- sourced, not run.
# The caller sets PRINTER before sourcing, then defines DEFAULT_CONFIG, MCUS,
# preflight_targets and flash_targets, then calls `upgrade_klipper "$@"`.
set -Eeuo pipefail

KLIPPER_DIR=$HOME/klipper
KLIPPY_ENV=$HOME/klippy-env
MOONRAKER=http://localhost:7125
# shellcheck disable=SC2034 # used by the sourcing script
CONFIG_DIR=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../printers/$PRINTER")

CONFIG_TOUCHED=0
KLIPPER_STOPPED=0

log() { printf '\n==> %s\n' "$*"; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() { command -v "$1" >/dev/null || die "missing required command: $1"; }
require_file() { [[ -f $1 ]] || die "missing $1"; }
require_device() { [[ -e $1 ]] || die "MCU not found at $1"; }
require_can_up() { [[ -n $(ip -o link show up dev "$1" 2>/dev/null) ]] || die "$1 is not up"; }

on_error() { printf 'ERROR: line %s: %s\n' "$1" "$2" >&2; }
trap 'on_error $LINENO "$BASH_COMMAND"' ERR

on_exit() {
  local rc=$?
  if ((CONFIG_TOUCHED)); then
    cp "$DEFAULT_CONFIG" "$KLIPPER_DIR/.config" && make -C "$KLIPPER_DIR" olddefconfig >/dev/null ||
      echo "WARNING: failed to restore $KLIPPER_DIR/.config" >&2
  fi
  if ((rc != 0 && KLIPPER_STOPPED)); then
    echo "ABORTED: klipper left stopped; fix the problem and re-run, or 'sudo systemctl start klipper'." >&2
  fi
}
trap on_exit EXIT

build() {
  log "Building $(basename "$1")"
  CONFIG_TOUCHED=1
  cp "$1" "$KLIPPER_DIR/.config"
  make -C "$KLIPPER_DIR" clean
  make -C "$KLIPPER_DIR" olddefconfig
  make -C "$KLIPPER_DIR" -j"$(nproc)"
}

# Linux host MCU ([mcu rpi]); installs klipper_mcu and restarts klipper-mcu.service.
flash_host_mcu() {
  build "$1"
  log "Flashing host MCU (mcu rpi)"
  sudo make -C "$KLIPPER_DIR" flash
}

moonraker_get() { curl -fsS --max-time 5 "$MOONRAKER$1"; }

preflight() {
  ((EUID != 0)) || die "run as your normal user, not root (sudo is used where needed)"
  [[ $(hostname -s) == "$PRINTER" ]] || die "this script is for $PRINTER, not $(hostname -s)"
  local cmd
  for cmd in git make curl jq; do require_cmd "$cmd"; done
  require_file "$DEFAULT_CONFIG"
  preflight_targets
  git -C "$KLIPPER_DIR" diff --quiet HEAD || die "$KLIPPER_DIR has modified tracked files"
  git -C "$KLIPPER_DIR" rev-parse --verify --quiet '@{u}' >/dev/null || die "$KLIPPER_DIR branch has no upstream"

  local state
  if state=$(moonraker_get /printer/objects/query?print_stats | jq -r .result.status.print_stats.state); then
    if [[ $state == printing || $state == paused ]]; then
      die "printer is $state; refusing to upgrade"
    fi
  else
    echo "WARNING: couldn't query print state from Moonraker; assuming not printing" >&2
  fi
}

update_source() {
  local assume_yes=$1 pending reply old_head
  log "Fetching $KLIPPER_DIR"
  git -C "$KLIPPER_DIR" fetch
  pending=$(git -C "$KLIPPER_DIR" log --oneline 'HEAD..@{u}')
  if [[ -n $pending ]]; then
    printf 'Incoming commits:\n%s\n' "$pending"
  else
    echo "Already up to date; will reflash $(git -C "$KLIPPER_DIR" describe --always --tags)."
  fi
  if ((! assume_yes)); then
    read -r -p "Stop klipper and flash all MCUs? [y/N] " reply
    [[ $reply == [yY]* ]] || die "cancelled"
  fi

  log "Stopping klipper"
  sudo systemctl stop klipper
  KLIPPER_STOPPED=1

  old_head=$(git -C "$KLIPPER_DIR" rev-parse HEAD)
  git -C "$KLIPPER_DIR" merge --ff-only '@{u}'
  if ! git -C "$KLIPPER_DIR" diff --quiet "$old_head" HEAD -- scripts/klippy-requirements.txt; then
    log "klippy-requirements.txt changed; updating klippy-env"
    "$KLIPPY_ENV/bin/pip" install -r "$KLIPPER_DIR/scripts/klippy-requirements.txt"
  fi
}

start_and_verify() {
  local info state host_version query status mcu version mismatch=0
  log "Starting klipper"
  sudo systemctl start klipper
  KLIPPER_STOPPED=0

  for _ in {1..30}; do
    info=$(moonraker_get /printer/info) || info='{}'
    state=$(jq -r '.result.state // "unknown"' <<<"$info")
    [[ $state == ready ]] && break
    sleep 2
  done
  [[ $state == ready ]] || die "klipper not ready (state: $state): $(jq -r '.result.state_message // ""' <<<"$info")"

  host_version=$(jq -r .result.software_version <<<"$info")
  query=$(printf '%s&' "${MCUS[@]}" | sed 's/ /%20/g; s/&$//')
  status=$(moonraker_get "/printer/objects/query?$query" | jq .result.status)
  for mcu in "${MCUS[@]}"; do
    version=$(jq -r --arg m "$mcu" '.[$m].mcu_version' <<<"$status")
    printf '  %-12s %s\n' "$mcu" "$version"
    [[ $version == "$host_version" ]] || mismatch=1
  done
  ((! mismatch)) || die "MCU firmware doesn't match klippy version $host_version"

  log "Done: klipper ready, all MCUs on $host_version"
}

upgrade_klipper() {
  local assume_yes=0
  case ${1:-} in
  -y) assume_yes=1 ;;
  "") ;;
  *) die "usage: $(basename "$0") [-y]" ;;
  esac
  preflight
  update_source "$assume_yes"
  flash_targets
  start_and_verify
}
