# ansible

Provisions a fresh Raspberry Pi 4 with everything a printer in this repo
needs _before_ `~/printer_data/config` gets symlinked to its
`printers/<hostname>` directory and Klipper/Moonraker take over — the
Klipper/Moonraker/webcam software stack, this repo's clone + symlink
swap, and the three Moonraker-managed plugins already referenced in each
printer's `moonraker.conf` (`moonraker-telegram-bot`,
`klipper_tmc_autotune`, Klippain Shake&Tune).

There's no web UI role: Mainsail/Fluidd run centrally off-host (on the
user's k8s cluster) and talk to each printer's Moonraker directly over
its `ssl_port` (7130 in both printers' `moonraker.conf`) — this
playbook's job is just to make sure Moonraker is listening there, not to
front it with anything local. nginx does still show up for one thing on
both printers: putting the webcam stream back behind HTTPS at a
`/webcam/` path (see `webcam_https_proxy` below) — Moonraker's own API
doesn't need it, but crowsnest has no TLS of its own. This started as a
vs-146-only setup (it already had an HTTPS `/webcam/` URL other things
depended on, from before crowsnest replaced its old hand-rolled camera
setup) and was later extended to klipper-v0 for consistency, and so
that a firewalled printer only ever exposes the webcam stream over
HTTPS rather than the bare HTTP port `webcam_port` opens directly (see
the `firewall` role).

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
- **Set up TLS certs for Moonraker's `ssl_port`, or the external
  `*.nimety.com` proxy in front of the k8s-hosted Mainsail/Fluidd.** Both
  printers' `moonraker.conf` already configure `ssl_port: 7130`, and
  klipper-v0's auto-discovers certs at
  `~/printer_data/certs/moonraker.{cert,key}` per the main repo's
  `CLAUDE.md` — this playbook assumes those certs already exist on each
  host and doesn't generate them.
- **Expose the webcam stream directly, on either current printer.**
  `group_vars/all.yml`'s default (`webcam_no_proxy: true`) would have
  crowsnest bind its stream port (`webcam_port`, 8080) directly on all
  interfaces, reachable straight over the LAN at
  `http://<hostname>.local:8080/stream` rather than through a `/webcam/`
  alias — but both `klipper-vs-146` and `klipper-v0` override that in
  their own `host_vars` (`webcam_no_proxy: false` +
  `webcam_https_proxy: true`), so crowsnest stays loopback-only and the
  stream is only reachable via nginx's HTTPS `/webcam/` path instead —
  see `webcam_https_proxy` in Layout below. A future printer that leaves
  the default in place would need `webcam_port` opened directly in the
  `firewall` role instead of `443`.
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
   Proxy behavior (`webcam_no_proxy`) defaults to streamed-directly
   (no proxy), but both current printers override it to `false` — see
   `webcam_https_proxy` below.
7. `webcam_https_proxy` — runs on both current printers, wherever
   `host_vars` sets `webcam_https_proxy: true`. A minimal nginx vhost
   whose only job is putting the webcam stream (crowsnest, kept
   loopback-only by `webcam_no_proxy: false`) behind HTTPS at a
   `/webcam/` path, reusing Moonraker's own certs — no static file
   serving, no Moonraker API proxying (that's natively handled by
   Moonraker's own `ssl_port` already). Originated on vs-146 (matching
   the HTTPS `/webcam/` URL it served before crowsnest replaced its old
   hand-rolled camera-streamer setup) and later extended to klipper-v0
   for the same reason, plus keeping the webcam off the open LAN once
   the `firewall` role is in place.
8. `moonraker_telegram_bot`, `klipper_tmc_autotune`, `shaketune` — the
   three plugins already referenced in each printer's `moonraker.conf`.
9. `firewall` — runs last. Installs `nftables` and renders
   `/etc/nftables.conf` with a default-drop `input` chain (logged, rate
   limited) that only opens SSH, Moonraker's `port`/`ssl_port`
   (7125/7130, both printers), mDNS, DHCPv4 client replies, and this
   printer's webcam access — `webcam_port` (8080) directly when
   `webcam_no_proxy: true`, or 443 when `webcam_https_proxy: true`
   fronts it instead (vs-146). SSH/Moonraker/webcam access is further
   scoped to `firewall_trusted_v4`/`firewall_trusted_v6`, the same
   LAN/link-local ranges as both printers' `moonraker.conf`
   `trusted_clients` — keep the two lists in sync if either changes.
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
