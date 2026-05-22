# mokerlink-backup: development notes

## Mokerlink switch CLI state machine

The switch CLI has three levels below the serial console:

| Prompt | State | Exit command |
|--------|-------|--------------|
| `Username:` | Login screen | (enter credentials) |
| `switch>` | User exec | `exit` → login prompt |
| `switch#` | Privileged exec | `exit` → user exec (`>`) |
| `(config)#` | Config mode | `end` → `#`, then `exit` × 2 |

Key facts:
- `exit` from `#` goes to `>` (user exec), **not** to the login prompt.
  A second `exit` is required to reach `Username:`.
- `enable` from `>` prompts for an **enable password**, which is separate
  from the login password.  Do not use `enable` in the serial prolog;
  navigate back to login and re-authenticate instead.
- Use an `exp_continue` loop to reach the login prompt from any state
  — do not enumerate states explicitly. Match any `[>#]` prompt, send
  `exit`, and call `exp_continue` to re-enter the expect block; stop on
  `"Username: "`. Bound with a `_tries` counter (limit 4) so the script
  fails fast if the target never appears.

## Serial transport design

- **Backup** (`get-config-serial`): issues `show {type}-config` over the
  serial channel; config text streams to stdout.  No TFTP server, no
  `sudo`.  The firmware echoes the command twice before the config body;
  strip with `| tail -n +3`.
- **Restore** (`set-config-serial`): switch pulls the config file from a
  TFTP server on the bootstrap host (`copy tftp://HOST/FILE
  startup-config`).  TFTP binds to port 69 → requires `sudo` on macOS/Linux.

## macOS serial access

macOS Docker Desktop cannot pass USB serial devices (`/dev/cu.usbserial-*`)
into containers.  Serial operations (`mokerlink-backup --transport serial`,
`mokerlink-restore --transport serial`) must be run natively from the repo
root, not via Docker.

On Linux, `docker run --device /dev/ttyUSB0` works normally.

## MST region name

Never use a hardware MAC address as the MST region name in
`start-config.cfg`.  Hardware MAC causes spanning-tree reconvergence on
hardware swap.  Use the switch hostname instead.
