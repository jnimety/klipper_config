# ansible

Provisions a fresh Raspberry Pi 4 with everything a printer in this repo
needs _before_ `~/printer_data/config` gets symlinked to its
`printers/<hostname>` directory and Klipper/Moonraker take over — the
Klipper/Moonraker/webcam software stack, this repo's clone + symlink
swap, and the three Moonraker-managed plugins already referenced in each
printer's `moonraker.conf` (`moonraker-telegram-bot`,
`klipper_tmc_autotune`, Klippain Shake&Tune).

There's no web UI role: Mainsail/Fluidd run centrally off-host (on the
user's k8s cluster), talking to each printer's Moonraker over what used
to be its own native `ssl_port` (7130). Every printer instead
reverse-proxies Moonraker's API/websocket through nginx alongside the
webcam, unconditionally (see `webcam_https_proxy` below) — this isn't a
per-printer option, every printer in the fleet works identically here.
nginx listens on 7130 itself (as well as 443) and proxies to Moonraker's
plain `port`, so existing Mainsail/Fluidd instance URLs on the k8s side
keep working unchanged — `moonraker.conf` no longer sets `ssl_port` at
all (it would otherwise conflict with nginx binding the same port).
nginx also puts the webcam stream back behind HTTPS at a `/webcam/`
path, since crowsnest has no TLS of its own. Both of these started as a
vs-146-only setup (it already had an HTTPS `/webcam/` URL other things
depended on, from before crowsnest replaced its old hand-rolled camera
setup) and were later made the fleet-wide default rather than a
per-printer toggle.

## What this does NOT do

- **Flash any MCU firmware.** Building/flashing the main board, the
  toolhead board, or the `[mcu rpi]` Linux target is hardware-specific,
  physical-access work — follow the main `README.md`'s "Upgrading
  Klipper firmware" runbooks by hand. This playbook installs and enables
  `klipper.service`/`klipper-mcu.service`, but `klipper-mcu.service`
  simply won't start until `/usr/local/bin/klipper_mcu` exists.
- **Keep anything updated.** Every `git clone` here uses `update: false`
  — the role's job is "make sure it's present" once, not "track
  upstream". Ongoing updates go through Moonraker's own update manager
  (for the plugins) or the main README's manual runbooks (for Klipper
  itself).
- **Provide `secrets.conf`.** It's gitignored and host-local by design
  (see the repo `CLAUDE.md`'s "Secrets" section). Copy it forward
  manually, same as the main README's deploy runbook already describes.
  The `klipper_config_repo` role just warns if it's missing.
- **Set up TLS certs, for nginx or the external `*.nimety.com` proxy in
  front of the k8s-hosted Mainsail/Fluidd.** Both printers'
  `~/printer_data/certs/moonraker.{cert,key}` already exist (per the
  main repo's `CLAUDE.md`) — this playbook assumes they're already
  there and doesn't generate them;
  `webcam_https_proxy`'s nginx vhost just reuses the same files directly.
- **Expose the webcam stream, or Moonraker, directly.** crowsnest always
  binds its stream port (`webcam_port`, 8080) to loopback only, and
  `moonraker.conf` never sets `ssl_port` — both are only ever reachable
  through nginx's HTTPS `/webcam/` path and proxied API/websocket (see
  `webcam_https_proxy` in Layout below). There's no per-printer toggle
  for this; it's how every printer in the fleet is provisioned.
- **Flash a fresh SD card or set the hostname/SSH.** Assumes Raspberry Pi
  OS is already imaged and reachable at `<hostname>.local` over SSH as
  the `jnimety` user with passwordless sudo (the RPi OS default).

## Layout

One role per concern, run in dependency order from `site.yml`:

1. `base` — apt prerequisites, hardware-access groups, SPI enable, the
   `printer_data` directory skeleton.
2. `security` — OS hardening shared with this user's other Ansible-managed
   hosts (see `~/workspace/home-network/k3s.nimety.com/ansible`'s own
   `security` role): a `/etc/sudoers.d/` drop-in for passwordless sudo,
   and an `/etc/ssh/sshd_config.d/` drop-in restricting SSH to the key
   exchange/cipher/MAC/host-key algorithms recommended by
   [ssh-audit's hardening guide](https://www.ssh-audit.com/hardening_guides.html)
   (`ssh-audit` itself is installed alongside so the result can be
   verified with `ssh-audit <hostname>.local`). The sshd drop-in is
   validated with `sshd -t` before the handler restarts `ssh`, so a bad
   config fails the playbook run instead of locking out a headless Pi.
3. `klipper_config_repo` — clones this repo to `~/klipper_config` and
   symlinks `~/printer_data/config` to `printers/<printer_name>`,
   automating the main README's "Deploying to a printer" steps.
4. `klipper` — clones Klipper, builds `klippy-env`, installs
   `klipper.service` + `klipper-mcu.service`.
5. `moonraker` — clones Moonraker, runs its official installer.
6. `crowsnest` — webcam streaming (every printer gets one now). Backend
   and camera settings (`webcam_mode`/`webcam_device`/`webcam_resolution`/
   `webcam_max_fps`/`webcam_custom_flags`) are set per printer in
   `host_vars` — group default is a generic USB/UVC webcam via
   `ustreamer`; see `host_vars/klipper-vs-146.yml` for the
   `camera-streamer` + libcamera variant its CSI Pi Camera Module needs.
   The stream always binds loopback-only (`no_proxy: false` in
   `crowsnest.conf`, hardcoded, not a variable) — `webcam_https_proxy`
   below is what actually exposes it.
7. `webcam_https_proxy` — runs on every printer unconditionally, not a
   per-host opt-in. One nginx vhost, reusing Moonraker's own certs,
   listening on both `443` and `moonraker_ssl_port` (7130, so existing
   external Mainsail/Fluidd configs pointed at the old `ssl_port` keep
   working unchanged), that puts both of the following behind HTTPS:
   - the webcam stream (crowsnest, always loopback-only) at `/webcam/`;
   - Moonraker's API/websocket, at the same paths (`/websocket`,
     `/printer/`, `/api/`, `/access/`, `/machine/`, `/server/`) its
     standard nginx/Mainsail/Fluidd configs already expect, proxied to
     `moonraker_port` (7125) in place of Moonraker's own `ssl_port` —
     `client_max_body_size 0` is set since gcode/firmware uploads go
     through here too.

   No static file serving — no local Mainsail/Fluidd UI is served here,
   that runs off-host. Before installing the vhost, this role also
   strips `ssl_port` from the _live_ `moonraker.conf` (not just the
   repo copy — `klipper_config_repo` clones with `update: false`, so a
   repo-only edit wouldn't reach an already-provisioned host) and
   restarts Moonraker, since nginx binding `7130` itself would otherwise
   conflict with Moonraker also trying to bind it. Originated on vs-146
   as webcam-only (matching the HTTPS `/webcam/` URL it served before
   crowsnest replaced its old hand-rolled camera-streamer setup), later
   extended to klipper-v0 for the same reason and then to proxying
   Moonraker too, and eventually made unconditional across the fleet
   rather than a pair of per-host toggles — every printer should look
   identical here.

8. `moonraker_telegram_bot`, `klipper_tmc_autotune`, `shaketune` — the
   three plugins already referenced in each printer's `moonraker.conf`.
9. `firewall` — runs last. Installs `nftables` and renders
   `/etc/nftables.conf` with a default-drop `input` chain (logged, rate
   limited) that only opens SSH, mDNS, DHCPv4 client replies, `443`, and
   `moonraker_ssl_port` (7130, owned by nginx) — Moonraker's plain
   `port` and `webcam_port` (8080) stay bound but unreachable from the
   LAN, since nginx reaches both over loopback. SSH/Moonraker/webcam
   access is further scoped to `firewall_trusted_v4`/
   `firewall_trusted_v6`, the same LAN/link-local ranges as both
   printers' `moonraker.conf` `trusted_clients` — keep the two lists in
   sync if either changes.
   `forward` is default-drop (these hosts don't route), `output` is
   left open. Because a bad rule here has no console to recover from on
   a headless Pi, the new ruleset is validated with `nft -c` before
   being written, and applying it schedules a `systemd-run` safety net
   that flushes the ruleset back open a few minutes later — cancelled
   only after this same playbook run confirms the SSH connection it's
   using still works.

Per-printer values live in `host_vars/<hostname>.yml`; shared defaults
(repo URLs, install paths, webcam settings) live in `group_vars/all.yml`.

## Usage

```
cd ansible
ansible-playbook site.yml                        # both printers
ansible-playbook site.yml --limit klipper-v0      # just one
ansible-playbook site.yml --check --diff          # dry run
```

### Prerequisites on the control machine

- `ansible-playbook` (this was written/tested against ansible-core 2.21).
- SSH access to `<hostname>.local` as `jnimety` with a key already
  authorized (`ssh-copy-id`), and passwordless sudo on that account.

### Prerequisites on each host

- The `jnimety` user needs its own SSH key authorized as a GitHub deploy
  key for `git@github.com:jnimety/klipper_config.git` (or override
  `klipper_config_repo_url` in `group_vars/all.yml` to an HTTPS URL with
  embedded credentials, or a token via `~/.git-credentials`, if you'd
  rather not manage per-host deploy keys).

### After the first run

- Enabling SPI may require a reboot before `/dev/spidev0.0` appears —
  `base` only reboots automatically if `reboot_if_required: true` is set
  (globally in `group_vars/all.yml` or per-host); it's left off by
  default. Reboot manually if the printer never comes up ready.
- For a USB/UVC webcam (the `ustreamer` default), check `ls -l
/dev/v4l/by-id/` on the host and set `webcam_device` in that printer's
  `host_vars` to the stable by-id path — `/dev/video0` (the default) can
  silently point at a different device after a reboot or a second USB
  device gets plugged in. klipper-v0 has no camera attached yet (checked
  via `lsusb`/`libcamera-hello` over SSH), so this only matters once one
  is actually plugged in.
- `moonraker.conf` will likely show an uncommitted diff after the first
  run (crowsnest's installer adds an `[update_manager crowsnest]` block,
  the same way the already-committed `klipper_tmc_autotune`/
  `Klippain-ShakeTune` blocks got there originally). Review and commit it
  yourself, same as any other host-generated change to this repo.
- Build/flash the actual MCU firmware per the main README before
  expecting `klippy` to report `ready`.
