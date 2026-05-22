# 1121citrus/mokerlink-backup

A CLI tool to download configuration backups from a [Mokerlink managed network switch](https://www.mokerlink.com/index.php?route=product/product&product_id=396).

## Contents

- [Contents](#contents)
- [Invoking the CLI](#invoking-the-cli)
- [Bootstrap a factory-reset switch](#bootstrap-a-factory-reset-switch)
  - [Serial console (recommended for first boot)](#serial-console-recommended-for-first-boot)
  - [HTTP web UI (no serial cable needed)](#http-web-ui-no-serial-cable-needed)
  - [SSH transports (running switch only)](#ssh-transports-running-switch-only)
- [Hardware swap — restore from factory reset](#hardware-swap--restore-from-factory-reset)
  - [Prerequisites](#prerequisites)
  - [Phase 1 — Prepare before touching any cables](#phase-1--prepare-before-touching-any-cables)
  - [Phase 2 — Bootstrap the replacement switch](#phase-2--bootstrap-the-replacement-switch)
  - [Phase 3 — Transfer cables](#phase-3--transfer-cables)
  - [Phase 4 — Cutover](#phase-4--cutover)
  - [Phase 5 — Verify](#phase-5--verify)
  - [Rollback](#rollback)
  - [Troubleshooting the swap](#troubleshooting-the-swap)
- [Synopsis](#synopsis)
- [CLI Usage](#cli-usage)
- [Examples](#examples)
  - [Download all configurations as a tarball](#download-all-configurations-as-a-tarball)
  - [Print the running configuration to stdout](#print-the-running-configuration-to-stdout)
  - [Selective download](#selective-download)
- [Legacy Service Mode](#legacy-service-mode)
  - [Run as a periodic cron job](#run-as-a-periodic-cron-job)
  - [Run a one-off backup to S3](#run-a-one-off-backup-to-s3)
  - [Docker Compose example](#docker-compose-example)
  - [Verify a backup](#verify-a-backup)
- [Configuration](#configuration)
  - [CLI parameters](#cli-parameters)
  - [Legacy service parameters](#legacy-service-parameters)
- [Building](#building)
- [Security](#security)

## Invoking the CLI

`mokerlink-backup` and `mokerlink-restore` are not installed on your host —
they run inside the `1121citrus/mokerlink-backup` Docker image.  Define these
shell functions (paste into `~/.bashrc` or `~/.zshrc`) so every example in
this document works as written from the directory that contains your `secrets/`
folder.

```bash
# Download switch configuration to a tar archive or stdout
mokerlink-backup() {
    docker run --rm \
        --volume "$(pwd)/secrets/mokerlink-password:/run/secrets/mokerlink-password:ro" \
        1121citrus/mokerlink-backup:latest \
        mokerlink-backup "$@"
}

# Restore switch configuration — http and ssh-cmd transports (no sudo required)
mokerlink-restore() {
    docker run --rm \
        --volume "$(pwd):/work" --workdir /work \
        --volume "$(pwd)/secrets/mokerlink-password:/run/secrets/mokerlink-password:ro" \
        1121citrus/mokerlink-backup:latest \
        mokerlink-restore "$@"
}
```

> **Serial and `ssh` transports** start a TFTP server on port 69/UDP, which
> requires host networking and elevated privileges.  They cannot be wrapped in
> a shell function; the bootstrap section shows the full `sudo docker run`
> form for those transports.

## Bootstrap a factory-reset switch

`mokerlink-restore` pushes a configuration file to a Mokerlink switch and
reboots it.  Four transport mechanisms are supported; choose based on what
hardware is available.

| Transport  | Cable required                | SSH needed | TFTP server        | `sudo`        |
|------------|-------------------------------|------------|--------------------|---------------|
| `serial`   | USB-to-serial + console cable | No         | Yes (auto-started) | Yes (port 69) |
| `http`     | Ethernet only                 | No         | No                 | No            |
| `ssh`      | Ethernet only                 | Yes        | Yes (auto-started) | Yes (port 69) |
| `ssh-cmd`  | Ethernet only                 | Yes        | No                 | No            |

### Serial console (recommended for first boot)

The serial transport works on any factory-reset switch regardless of whether
SSH or the web UI is reachable.  It requires a USB-to-serial adapter, the
RJ45 console cable shipped with the switch, and `sudo` access on the
bootstrap laptop.

> **macOS vs Linux:** Docker Desktop on macOS runs inside a Linux VM.
> USB serial devices (`/dev/cu.usbserial-*`) and direct network-interface
> binds are not available inside the VM, so the serial transport must run
> natively from the repository checkout.  On Linux, Docker has full access
> to host devices and networking.

---

#### macOS — native (no Docker)

**Hardware setup:**

1. Connect the USB-to-serial adapter to the switch's RJ45 console port.
2. Connect an Ethernet cable from the laptop to any switch port.
3. Set the Ethernet interface to a static address in `192.168.2.0/24` —
   for example, `192.168.2.10` (any address other than `192.168.2.1`).
4. Confirm the switch is reachable:

   ```console
   $ ping -c 3 192.168.2.1
   ```

**Restore command** — run from the repository root:

```console
$ sudo bash "$(pwd)/src/bin/mokerlink-restore" \
      --transport serial \
      --config start-config.cfg \
      --tftp-host 192.168.2.10
```

- Replace `192.168.2.10` with the IP you configured in step 3.
- Replace `start-config.cfg` with the configuration file to restore.
- The serial port is auto-detected (`/dev/cu.usbserial-*`).
  Use `--port /dev/cu.usbserial-XXXX` to override.
- The factory-default password (`admin`) is used automatically.
  Add `--password YOUR_PASS` if the switch already has a custom password.

The script starts the macOS built-in TFTP daemon, opens the serial console,
pushes the config, and reboots the switch.  Total time: about two minutes.

---

#### Linux — Docker

**Hardware setup:** same steps 1–4 as macOS above.

**Restore command:**

```console
$ sudo docker run --rm \
      --network host --privileged \
      --volume "$(pwd):/work" --workdir /work \
      --device /dev/ttyUSB0 \
      1121citrus/mokerlink-backup:latest \
      mokerlink-restore --transport serial --config start-config.cfg
```

- Replace `/dev/ttyUSB0` with the actual serial device.
  Check with `ls /dev/ttyUSB* /dev/ttyACM*`.
- The factory-default password (`admin`) is used automatically.
  To supply a custom password, add:
  `--volume "$(pwd)/secrets/mokerlink-password:/run/secrets/mokerlink-password:ro"`

### HTTP web UI (no serial cable needed)

> **Note:** The HTTP transport requires one-time endpoint discovery against a
> live switch using browser developer tools.  See `doc/http-endpoints.md` once
> that document is created (Phase D).

### SSH transports (running switch only)

The `ssh` and `ssh-cmd` transports require SSH to be enabled on the switch.
SSH is **not** enabled on factory-reset units; use `serial` or `http` for
first boot.

**`ssh` transport** — uses TFTP to transfer the config file; requires `sudo`
for TFTP port 69:

```console
$ sudo docker run --rm \
      --network host --privileged \
      --volume "$(pwd):/work" --workdir /work \
      --volume "$(pwd)/secrets/mokerlink-password:/run/secrets/mokerlink-password:ro" \
      1121citrus/mokerlink-backup:latest \
      mokerlink-restore \
          --transport ssh \
          --config start-config.cfg \
          --host switch-1
```

**`ssh-cmd` transport** — parses the config file and replays commands
interactively; no TFTP server and no `sudo` needed.  Uses the
`mokerlink-restore` function defined in [Invoking the CLI](#invoking-the-cli):

```console
$ mokerlink-restore \
    --transport ssh-cmd \
    --config start-config.cfg \
    --host switch-1
```

Both SSH transports use legacy RSA key exchange flags (`+ssh-rsa`) because
the Mokerlink firmware does not support modern key exchange algorithms.  The
switch host key is accepted unconditionally because the firmware regenerates
it on every factory reset.

## Hardware swap — restore from factory reset

Use this procedure when replacing a failed or damaged switch with a new unit
of the same model.  The goal is to make the replacement switch electrically
transparent to the rest of the network — same configuration, same port
assignments, minimal disruption.

> **Estimated disruption:** 5–10 minutes from cable transfer to full network
> recovery, assuming all preparation steps are done in advance.
>
> **Rollback at any point:** transfer all cables back to the original switch.
> The network heals within seconds.  Keep the original switch powered and
> uncabled until Phase 5 verification passes — it is your safety net.

---

### Prerequisites

Before starting, confirm you have:

- [ ] A verified backup configuration file (`start-config.cfg`) from the
      switch being replaced
- [ ] The USB-to-serial adapter and the RJ45 console cable shipped with
      the switch
- [ ] Admin access to the firewall web UI or SSH console
- [ ] The replacement switch (factory reset, still in bootstrap state)
- [ ] The laptop with this repository checked out and `sudo` access

---

### Phase 1 — Prepare before touching any cables

Complete these steps while the original switch is still running and the
network is healthy.

#### 1.1 — Find the replacement switch's MAC address

The base MAC address is printed on the label on the bottom of the unit.
Write it down — you need it in the next step.

The switch uses a block of MAC addresses for its ports, all derived from
the base MAC.  The management interface uses the base MAC directly.

#### 1.2 — Update the DHCP reservation on the firewall

The firewall assigns the switch its fixed management IP via a DHCP
reservation keyed to the switch's MAC address.[^dhcp-mac]  The replacement
unit has a different MAC and will not receive the reserved IP unless the
reservation is updated first.

On **pfSense / OPNsense**:

- Navigate to **Services → DHCP Server → [management VLAN interface]**
- Scroll to **DHCP Static Mappings**
- Find the entry for the switch and replace the MAC address with the
  replacement unit's base MAC
- Save — no service restart required

> **Why before Phase 3?** If skipped, the replacement switch gets a
> random DHCP address.  Locating it later requires serial console access.

#### 1.3 — Check the spanning-tree MST region name in the config file

Open `start-config.cfg` and find this block:

```text
spanning-tree mst configuration
 name "..."
```

If the `name` field contains a MAC address (hex octets separated by
colons, e.g. `"1C:2A:A3:1D:0F:99"`), it is set to the **old switch's
hardware MAC**.[^mst]  Change it to a stable, hardware-independent
identifier — the switch hostname works well:

```text
spanning-tree mst configuration
 name "switch-1"
```

Save the updated config file before proceeding.

---

### Phase 2 — Bootstrap the replacement switch

Follow the [serial console procedure](#serial-console-recommended-for-first-boot)
using the replacement switch and the config file updated in Phase 1.

Summary of what that procedure does:

1. Connect the USB-to-serial adapter to the replacement switch's console port.
2. Connect a direct Ethernet cable between the laptop and any switch port;
   set the laptop's interface to a static address in `192.168.2.0/24`
   (e.g., `192.168.2.10`).
3. Run `mokerlink-restore --transport serial --config start-config.cfg
   --tftp-host 192.168.2.10` to push the config and reboot the switch.
4. Remove the bootstrap cabling (serial adapter and direct Ethernet).

At the end of Phase 2, the replacement switch holds the production
configuration.  The original switch is still running with all production
cables attached.

---

### Phase 3 — Transfer cables

1. **Photograph the current cable layout** before touching anything.
   A photo is faster and more reliable than re-reading port labels when
   re-cabling under pressure.

2. Transfer every cable from the original switch to the replacement switch,
   **matching port numbers exactly**: port 1 → port 1, port 2 → port 2,
   and so on.

3. Leave the original switch powered but uncabled — it is the rollback
   target if anything goes wrong.

---

### Phase 4 — Cutover

> **Order matters.** The ARP flush (step 4.2) must happen before the
> router reboot (step 4.4) so that the router re-learns MAC addresses
> from a clean state rather than re-populating its cache from stale data.

#### 4.1 — Wait for the replacement switch to finish booting

After the last cable is seated, wait for the port LEDs to stabilize
(approximately 60 seconds).  The switch is running the production config
at this point but the rest of the network still has stale Layer-2
information.

#### 4.2 — Flush the ARP table on the firewall  ⚠ critical step

**This is the most important and most easily missed step.**

When the replacement switch comes up, every IP address in the network is
unchanged but every MAC address has changed.  The firewall's ARP cache
still maps those IPs to the old switch's physical addresses.[^arp]
Until the cache is flushed, packets for the switch management IP and for
any device that did not reboot will be silently dropped.

**pfSense / OPNsense — web UI:**
Diagnostics → ARP Table → **Clear ARP Table**

**pfSense / OPNsense — SSH or console shell:**

```console
# arp -d -a
```

**Generic Linux firewall / router:**

```console
# ip neigh flush all
```

#### 4.3 — Flush the ARP table on any other Layer-3 device

If there is a separate upstream router between the firewall and the ISP,
reboot it or flush its ARP table via its management interface.  The same
stale-cache problem applies to any device that has a MAC-to-IP mapping
for addresses in your network.

#### 4.4 — Reboot the router

A full reboot clears any remaining Layer-2 forwarding tables and ARP
state that a manual flush might not reach.  For most home routers,
power-cycling is the safest approach.  Wait for the router to finish
booting (~90 seconds) before running verification.

---

### Phase 5 — Verify

Allow two minutes for all devices to re-register after the router
comes back up, then confirm:

| Check | Command / location | Expected result |
|---|---|---|
| Switch responds to ping | `ping -c 3 <SWITCH-IP>` | Replies, <2 ms |
| Switch web UI loads | Browser → `http://<SWITCH-IP>` | Login page loads |
| Firewall ARP table | Diagnostics → ARP Table | Switch entry shows **new** MAC |
| DHCP lease table | Services → DHCP Leases | Switch shows correct reserved IP |
| Upstream connectivity | Speed test from a wired client | Completes without failure |
| All managed VLANs | Ping a device on each VLAN | All reply |

If all checks pass: power off the original switch.

If any check fails: see [Rollback](#rollback) and
[Troubleshooting the swap](#troubleshooting-the-swap) below.

---

### Rollback

If the network does not recover fully within five minutes of Phase 4:

1. Transfer all cables back to the original switch (Phase 3 in reverse).
2. The network heals within seconds — the original switch never lost power.
3. Flush the firewall ARP table again (step 4.2) to clear any state
   accumulated during the failed cutover.

Investigate the failure before attempting the swap again.

---

### Troubleshooting the swap

#### Switch management IP unreachable

Most common cause: stale ARP entry on the firewall.  Verify:

```console
# arp -n <SWITCH-IP>
```

If the output shows the **old** MAC address, the flush in step 4.2 did
not complete.  Repeat the flush; then ping the switch immediately to
trigger fresh ARP resolution.

If no entry appears at all, the DHCP reservation (step 1.2) may not have
been updated.  Connect via serial console to check the management IP the
switch actually received.

#### Firewall CPU spikes to ~100% every 1–2 minutes

Cause: the firewall has stale ARP entries for multiple IPs simultaneously.
It is sending ARP probes, receiving no reply, and retrying on a
~90-second cycle.[^arp-retry]

Fix: repeat step 4.2 (flush all ARP).  If specific devices remain
unreachable, reboot those devices — when they come back up they send a
*gratuitous ARP* that immediately updates every neighbour's cache.[^garp]

#### Port LEDs flapping or intermittent connectivity after reboot

Cause: if step 1.3 was skipped and the `spanning-tree mst configuration
name` still contains the old switch's hardware MAC, spanning tree treats
the replacement as a different MST region.[^mst]  Every uplink port goes
through a Listening → Learning → Forwarding convergence cycle
(~30–50 seconds) rather than transitioning instantly.

Fix: update `start-config.cfg` per step 1.3, re-push via `ssh-cmd`
transport, and reboot the switch:

```console
$ mokerlink-restore \
    --transport ssh-cmd \
    --config start-config.cfg \
    --host <SWITCH-IP>
```

---

### Background

[^dhcp-mac]: **DHCP reservations are keyed to MAC address.**  DHCP works
by assigning IPs to clients identified by their MAC (hardware) address.
A static mapping or reservation tells the DHCP server "always give this
MAC this IP."  Because the replacement switch has a different MAC than
the original, it presents as a completely unknown client.  Depending on
firewall policy it either receives a dynamic address from the general
pool, or is denied entirely.

[^mst]: **Spanning Tree MST region name.**  IEEE 802.1s Multiple Spanning
Tree groups switches into *regions* — switches agree on the same region
name, revision number, and VLAN-to-instance table before they form a
region together.  Switches in different regions see each other as a
single opaque bridge at the boundary and re-run spanning tree across that
boundary.  If the region name is a hardware MAC address, a replacement
switch will advertise a different name, causing the uplink to go through
a full STP convergence cycle (~30–50 s) on every reboot and potentially
a brief forwarding loop during the transition.  A fixed hostname-based
name eliminates this entirely.  See
[IEEE 802.1s](https://www.ieee802.org/1/pages/802.1s.html) for the
specification.

[^arp]: **ARP caching.**  ARP (Address Resolution Protocol, RFC 826) is
how Layer-3 devices find the Layer-2 MAC address for a known IP.  The
result is cached in an *ARP table* — typically for 10–20 minutes on
Linux/BSD, longer on some commercial devices — to avoid broadcasting an
ARP request on every packet.  When a switch is replaced, the IPs stay
the same but the MACs change.  Any device with a stale ARP entry for an
address on or behind the switch will silently drop packets until the
entry expires or is manually cleared.

[^arp-retry]: **ARP probe retry cycle.**  When a cached ARP entry is
about to expire, the host first sends a unicast *probe* to the cached MAC.
If there is no reply (because the hardware is gone), it falls back to a
broadcast ARP *request*.  On Linux the default probe interval is ~30 s
with three retries; on BSD/pfSense it is approximately 90–120 s.  Each
unresolvable cache entry generates a brief CPU spike on the router or
firewall, producing the characteristic ~100% spikes at regular intervals
that indicate multiple stale ARP entries — one spike per entry per probe
cycle.

[^garp]: **Gratuitous ARP.**  When a device boots or its IP configuration
changes, it broadcasts an unsolicited ARP reply — a *gratuitous ARP* —
announcing "I am IP x.x.x.x and my MAC is AA:BB:CC:DD:EE:FF."  Every
device on the subnet that receives this immediately updates its ARP cache
for that IP.  This is why rebooting end devices (servers, cameras, etc.)
after a switch swap clears stale ARP entries faster than waiting for the
natural cache-expiry cycle.

---

## Synopsis

`mokerlink-backup` is a CLI packaged inside the `1121citrus/mokerlink-backup`
Docker image.  It downloads the running, startup, and/or backup configurations
from a [Mokerlink managed network switch](https://www.mokerlink.com/index.php?route=product/product&product_id=396)
and streams them to stdout as a tar archive or raw text.  The script uses the
[Cisco-inspired CLI](https://www.mokerlink.com/index.php?route=product/product/download&download_id=20)
over SSH.  Define the shell function in [Invoking the CLI](#invoking-the-cli)
to invoke it without typing the full `docker run` incantation each time.

A backup user must be provisioned on the switch with `Admin` privileges.
Firewall rules must allow the container to reach the switch's SSH port (22/tcp).

## CLI Usage

```text
mokerlink-backup [options]

Download a backup of a Mokerlink managed network switch.

Options:
  -?,--help              Display this help text
  -v,--version           Display command version
  -a,--all               Include all configurations (default)
  -r,--running           Include running configuration
     --no-running        Exclude running configuration
  -s,--startup           Include startup configuration
     --no-startup        Exclude startup configuration
  -b,--backup            Include backup configuration
     --no-backup         Exclude backup configuration
  -f,--format FMT        Output format: 'raw' or 'tar'
                         (env: MOKERLINK_FORMAT; default: 'tar')
  -H,--host HOST         Switch hostname or IP (env: MOKERLINK_HOST)
  -u,--user USER         SSH username (env: MOKERLINK_USER;
                         default: remote-backup)
  -p,--password PW       Password (env: MOKERLINK_PASSWORD)
  -P,--password-file FILE
                         Password file (env: MOKERLINK_PASSWORD_FILE;
                         default: /run/secrets/mokerlink-password)
```

Connection parameters may also be supplied via environment variables (see
[CLI parameters](#cli-parameters) below).

> **Note on `-h`:** There is no `-h` flag — `-H` (uppercase) is the host option.
> Use `-?` or `--help` to display help text.

## Examples

### Download all configurations as a tarball

```console
$ docker run --rm \
      -v ./secrets/mokerlink-password:/run/secrets/mokerlink-password:ro \
      1121citrus/mokerlink-backup:latest \
      mokerlink-backup --host switch --user backup-user > switch-backup.tar
```

Or using environment variables:

```console
$ docker run --rm \
      -e MOKERLINK_HOST=switch \
      -e MOKERLINK_USER=backup-user \
      -v ./secrets/mokerlink-password:/run/secrets/mokerlink-password:ro \
      1121citrus/mokerlink-backup:latest \
      mokerlink-backup > switch-backup.tar
```

### Print the running configuration to stdout

```console
$ docker run --rm \
      -v ./secrets/mokerlink-password:/run/secrets/mokerlink-password:ro \
      1121citrus/mokerlink-backup:latest \
      mokerlink-backup --host switch --user backup-user --running --format raw
SYSTEM CONFIG FILE ::= BEGIN
! System Description: KT-NOS POE-G244GSM Switch
! System Version: v1.0.0.27
! System Name: switch
! System Up Time: 0 days, 23 hours, 9 mins, 34 secs
!
    .
    .
    .
```

### Selective download

These examples use the `mokerlink-backup` function defined in
[Invoking the CLI](#invoking-the-cli).

Include only running and startup configs (exclude backup):

```console
$ mokerlink-backup --host switch -u backup-user --running --startup > partial.tar
```

Include all except startup:

```console
$ mokerlink-backup --host switch -u backup-user --no-startup > partial.tar
```

---

## Legacy Service Mode

The image can also run as a Docker Compose service to periodically perform
backups and transfer them to S3.  This behavior is retained for backward
compatibility.

> A future refactoring will replace the cron service role with a dedicated
> scheduler (e.g. [willfarrell/docker-crontab](https://github.com/willfarrell/docker-crontab)
> or [mcuadros/ofelia](https://github.com/mcuadros/ofelia)) that invokes
> `mokerlink-backup` directly.  Once that is done the legacy `backup`,
> `startup`, and `healthcheck` scripts — and the S3/GPG dependencies — can
> be removed, greatly reducing the attack surface.

### Run as a periodic cron job

```console
$ docker run -i --rm \
      -e AWS_S3_BUCKET_NAME=backups-bucket \
      -e COMPRESSION=bzip2 \
      -e CRON_EXPRESSION='*/15 * * * *' \
      -e MOKERLINK_HOST=switch \
      -e MOKERLINK_USER=remote-backup \
      -v ./secrets/aws-config:/run/secrets/aws-config:ro \
      -v ./secrets/mokerlink-password:/run/secrets/mokerlink-password:ro \
      -v ./secrets/gpg-passphrase:/run/secrets/gpg-passphrase:ro \
      -v /etc/localtime:/etc/localtime:ro \
      1121citrus/mokerlink-backup:latest
```

Example log output:

```console
[INFO] 20250922T120714 startup create env file /root/.env
[INFO] 20250922T120714 startup export AWS_CONFIG_FILE='/run/secrets/aws-config'
[INFO] 20250922T120714 startup export AWS_DRYRUN='false'
[INFO] 20250922T120714 startup export AWS_S3_BUCKET_NAME='backups-bucket'
[INFO] 20250922T120714 startup export COMPRESSION='bzip2'
[INFO] 20250922T120714 startup export CRON_EXPRESSION='*/15 * * * *'
[INFO] 20250922T120714 startup export DEBUG='false'
[INFO] 20250922T120714 startup export GPG_CIPHER_ALGO='aes256'
[INFO] 20250922T120714 startup export GPG_PASSPHRASE='**REDACTED**'
[INFO] 20250922T120714 startup export GPG_PASSPHRASE_FILE='/run/secrets/gpg-passphrase'
[INFO] 20250922T120714 startup export MOKERLINK_HOST='switch'
[INFO] 20250922T120714 startup export MOKERLINK_PASSWORD='**REDACTED**'
[INFO] 20250922T120714 startup export MOKERLINK_PASSWORD_FILE='/run/secrets/mokerlink-password'
[INFO] 20250922T120714 startup export MOKERLINK_USER='remote-backup'
[INFO] 20250922T120714 startup export TAILSCALE_HOST=''
[INFO] 20250922T120714 startup export TZ='UTC'
[INFO] 20250922T120714 startup installing cron.d entry: /usr/local/bin/backup
[INFO] 20250922T120714 startup mkdir: created directory '/var/spool/cron'
[INFO] 20250922T120714 startup mkdir: created directory '/var/spool/cron/crontabs'
[INFO] 20250922T120714 startup mode of '/var/spool/cron/crontabs' changed from 0700 to 0755
[INFO] 20250922T120714 startup mode of '/var/spool/cron/crontabs/root' changed from 0644 to 0600
[INFO] 20250922T120714 startup crontab: */15 * * * * /usr/local/bin/backup 2>&1
[INFO] 20250922T120714 startup handing the reins over to cron daemon
   .
   .
   .
[INFO] 20250922T161500 backup begin backup
[INFO] 20250922T161500 backup download 'running' configuration from 'switch'
[INFO] 20250922T161511 backup completed download of 'running' configuration from 'switch'
[INFO] 20250922T161511 backup download 'startup' configuration from 'switch'
[INFO] 20250922T161516 backup completed download of 'startup' configuration from 'switch'
[INFO] 20250922T161516 backup download 'backup' configuration from 'switch'
[INFO] 20250922T161523 backup completed download of 'backup' configuration from 'switch'
[INFO] 20250922T161523 backup compressing backup with bzip2: 20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2
[INFO] 20250922T161523 backup encrypting backup with 'gpg' (GnuPG)
[INFO] 20250922T161523 backup downloaded '20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar' to '20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg'
[INFO] 20250922T161524 backup finish backup
```

### Run a one-off backup to S3

```console
$ docker run -i --rm \
      -e AWS_S3_BUCKET_NAME=backups-bucket \
      -e COMPRESSION=gzip \
      -e MOKERLINK_HOST=switch \
      -e MOKERLINK_USER=remote-backup \
      -v ./secrets/aws-config:/run/secrets/aws-config:ro \
      -v ./secrets/mokerlink-password:/run/secrets/mokerlink-password:ro \
      -v ./secrets/gpg-passphrase:/run/secrets/gpg-passphrase:ro \
      -v /etc/localtime:/etc/localtime:ro \
      1121citrus/mokerlink-backup backup
```

### Docker Compose example

```yml
services:
  mokerlink-backup:
    container_name: mokerlink-backup
    image: 1121citrus/mokerlink-backup:latest
    restart: always
    environment:
      - AWS_S3_BUCKET_NAME=${AWS_S3_BUCKET_NAME:-backup-bucket}
      - COMPRESSION=xz
      - CRON_EXPRESSION=${CRON_EXPRESSION:-15 3 * * *}
      - MOKERLINK_HOST=switch
      - MOKERLINK_USER=remote-backup
      - TZ=${TZ:-US/Eastern}
    volumes:
      - /etc/localtime:/etc/localtime:ro
    secrets:
      - aws-config
      - gpg-passphrase
      - mokerlink-password

secrets:
  aws-config:
    file: ./secrets/aws-config
  gpg-passphrase:
    file: ./secrets/gpg-passphrase
  mokerlink-password:
    file: ./secrets/mokerlink-password
```

### Verify a backup

```console
$ aws s3 cp s3://backups-bucket/20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.sha256 -
3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4  20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar
$ aws s3 cp --quiet s3://backups-bucket/20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg - \
    | gpg --passphrase-file ./secrets/gpg-passphrase --decrypt --batch --quiet \
    | bunzip2 | sha256sum
3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4  -
```

---

## Configuration

### CLI parameters

| Parameter | Option | Environment variable | Default | Notes |
| --- | --- | --- | --- | --- |
| Host | `-H`,`--host` | `MOKERLINK_HOST` | `${TAILSCALE_HOST}` | Hostname or IP of the switch. `MOKERLINK_HOST` overrides `TAILSCALE_HOST`. |
| User | `-u`,`--user` | `MOKERLINK_USER` | `remote-backup` | SSH username. |
| Password | `-p`,`--password` | `MOKERLINK_PASSWORD` | _none_ | Switch login password. Prefer `--password-file`. |
| Password file | `-P`,`--password-file` | `MOKERLINK_PASSWORD_FILE` | `/run/secrets/mokerlink-password` | File containing the password. Intended as a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/). |
| Format | `-f`,`--format` | `MOKERLINK_FORMAT` | `tar` | Output format: `raw` or `tar`. |
| Tailscale host | — | `TAILSCALE_HOST` | _none_ | Fallback hostname when `MOKERLINK_HOST` is unset. |
| Debug | — | `DEBUG` | `false` | Set to `true` to enable `xtrace`/`verbose`. **WARNING:** exposes passwords in logs. |

### Legacy service parameters

These environment variables are used by the `startup` and `backup` scripts
when the image runs as a Docker Compose service.

| Variable | Default | Notes |
| --- | --- | --- |
| `AWS_CONFIG_FILE` | `/run/secrets/aws-config` | AWS credentials file. Intended as a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/). |
| `AWS_DRYRUN` | `false` | Set to `true` to pass `--dryrun` to AWS CLI commands. |
| `AWS_S3_BUCKET_NAME` | _required_ | S3 bucket for uploads. May include a path prefix, e.g. `your-bucket/backups/daily` (no trailing `/`). |
| `COMPRESSION` | `none` | Compression algorithm: `bzip`, `bzip2`, `bzip3`, `gz`, `gzip`, `lzma`, `lzo`, `lzop`, `none`, `pigz`, `pixz`, `xz`, `zip`. |
| `CRON_EXPRESSION` | `@daily` | Standard cron expression. See [crontab.guru](https://crontab.guru/). |
| `GPG_CIPHER_ALGO` | `aes256` | GnuPG symmetric encryption cipher. |
| `GPG_PASSPHRASE` | _none_ | GnuPG passphrase. Prefer `GPG_PASSPHRASE_FILE`. |
| `GPG_PASSPHRASE_FILE` | `/run/secrets/gpg-passphrase` | File containing the GnuPG passphrase. Intended as a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/). |
| `TZ` | `UTC` | Timezone for cron scheduling, e.g. `America/New_York`. |

---

## Building

Use the `build` script at the project root.  It wraps `docker buildx` and
handles multi-arch targets, SBOM/provenance attestations, and version tagging.

```console
# Local dev build — no push, tagged "dev-<git-sha>"
./build

# Release build — push version 1.2.3 and re-tag latest
./build --push --version 1.2.3

# Dry-run: print the buildx command without executing it
./build --push --version 1.2.3 --dry-run

# Full help
./build --help
```

Prerequisites: `docker` with the `buildx` plugin and QEMU binfmt helpers
installed for cross-platform builds:

```console
docker run --rm --privileged tonistiigi/binfmt --install all
```

## Security

See [SECURITY.md](SECURITY.md) for the full threat model, credential handling
guidance, SSH host-key verification trade-offs, and S3 hardening recommendations.
Report vulnerabilities through the
[GitHub Security tab](https://github.com/1121citrus/mokerlink-backup/security).
