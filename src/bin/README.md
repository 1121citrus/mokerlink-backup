# src/bin — script reference

Scripts installed to `/usr/local/bin` inside the container image.

---

## Script inventory

| Script | Role | Entry point |
| --- | --- | --- |
| `mokerlink-backup` | **Primary CLI** — downloads switch configs, streams tar or raw text to stdout | user / cron |
| `get-config` | SSH engine — opens an `expect`-driven SSH session and captures one config type | called by `mokerlink-backup` |
| `get-running-config` | Wrapper: `get-config running "$@"` | backward-compat |
| `get-startup-config` | Wrapper: `get-config startup "$@"` | backward-compat |
| `get-backup-config` | Wrapper: `get-config backup "$@"` | backward-compat |
| `backup` | Legacy service script — fetches all configs, compresses, encrypts, uploads to S3 | cron (via `startup`) |
| `startup` | Container entrypoint — writes `.env`, installs crontab, hands off to `crond` | `CMD` in Dockerfile |
| `healthcheck` | Docker `HEALTHCHECK` — verifies `crond` is running and the crontab is configured | Docker daemon |

---

## Data flow

### CLI mode (primary)

```text
caller
  └─ mokerlink-backup [opts]
        ├─ get-config running   host user   (via bash, MOKERLINK_PASSWORD in env)
        ├─ get-config startup   host user
        └─ get-config backup    host user
              └─ expect → ssh → Mokerlink firmware CLI
                    → "show <type>-config" output → stdout
        └─ tar -c *.xml → stdout   (or cat raw text → stdout)
```

### Legacy service mode

```text
Docker CMD
  └─ startup
        └─ crond (daemon)
              └─ backup  (on schedule)
                    └─ mokerlink-backup  (streams tar to workdir)
                    └─ compress  (bzip2 / gzip / xz / …)
                    └─ gpg --symmetric  (optional)
                    └─ aws s3 mv  →  S3 bucket
```

---

## `mokerlink-backup`

The user-facing CLI.  Parses options, resolves credentials, calls `get-config`
for each selected configuration type, and either tars the XML files to stdout
or cats the raw text.

### Config selection model

Option flags (`-r`, `-s`, `-b`, `--all`, `--no-*`) use `true`/`false` as shell
commands (exit codes 0/1), not as string values.  The pattern
`if ! "${has_positive}"; then … fi` tests the exit code of the named command.
If no positive flag was given, all three configs are selected by default.

### Filename sidecar (`MOKERLINK_BACKUP_NAME_FILE`)

The tar archive is named after the switch hostname and firmware version, which
are discovered only during the SSH session.  When `MOKERLINK_BACKUP_NAME_FILE`
is set, `mokerlink-backup` writes the computed basename to that path after the
last config is downloaded.  `backup` uses this mechanism to rename the output
file without reparsing the tar stream.

---

## `get-config`

The SSH engine.  Uses `expect` (Tcl) to drive an interactive SSH session
against the Mokerlink firmware CLI.

### Why `expect`?

The Mokerlink firmware presents an application-layer username/password prompt
over SSH and does not support public-key authentication or batch/non-interactive
modes.  `expect` is the only practical way to automate this interaction.

### SSH flags

| Flag | Reason |
| --- | --- |
| `-F /dev/null` | Ignore `~/.ssh/config`; prevent local settings from interfering |
| `StrictHostKeyChecking=no` | Firmware regenerates the host key on every factory reset |
| `UserKnownHostsFile=/dev/null` | Prevents stale known-hosts entries from blocking automation |
| `+ssh-rsa` (host key and pubkey) | Firmware requires legacy RSA; modern OpenSSH disables it by default |

### `expect` session walkthrough

1. `log_user 0` — suppress output; only the config body should reach stdout
2. SSH connect → firmware presents `Username:` / `Password:` prompts
3. `terminal length 0` — disable firmware paging so `show` output is not broken up with `--More--` prompts
4. `send "show <type>-config\r"`
5. `log_user 1` — start capturing output
6. Wait for `#` prompt (end of config body)
7. `log_user 0` — stop capturing
8. Two-level exit: `exit` from privileged exec (`#`) to user exec (`>`), then `exit` to close the session
9. The raw output includes two echo-back lines before `SYSTEM CONFIG FILE ::= BEGIN`; `tail -n +3` strips them

### Single-quoted heredoc delimiter

```bash
/usr/bin/env expect "${expect_args[@]}" <<-'__END_OF_SCRIPT__'
```

The `'` quoting prevents bash from expanding the Tcl `$env(...)` references
inside the heredoc before `expect` reads them.  All parameters are passed via
exported environment variables (`EXPECT_CONFIG`, `EXPECT_HOSTNAME`, etc.).
Passwords are never passed as positional arguments to avoid exposure in `ps(1)`.

### `get-running-config` / `get-startup-config` / `get-backup-config`

Thin wrappers that prepend the config-type argument and delegate to
`get-config`.  They predate the unified `get-config` dispatcher and are
retained for backward compatibility.

---

## `backup` (legacy service script)

Orchestrates the full backup pipeline: download → compress → encrypt → upload.

### Key design points

**Filename sidecar** — `mokerlink-backup` is called with
`MOKERLINK_BACKUP_NAME_FILE` pointing to a temp file.  After the download, the
basename written there is used to rename the output archive.

**SHA256 ordering** — The checksum is computed against the uncompressed tar,
before any compression or encryption.  Verification therefore requires
decrypting and decompressing first; see *Verify a backup* in the project README.

**`aws s3 mv`** — The AWS CLI `mv` sub-command uploads the file and then deletes
the local copy on success.  This prevents large archives from accumulating in
the workdir across successive cron runs.

**Compression** — All compression is read-from-stdin / write-to-stdout to avoid
creating additional copies of the (potentially large) tar file in the workdir.

---

## `startup`

Container entrypoint for legacy service mode.  Writes all runtime configuration
to `~/.env` (the file `crond` and `backup` source at startup), installs a
crontab entry, and runs `crond -l 2 -f` in the foreground.  The startup script
itself remains PID 1; `crond` runs as a child process.

The `.env` write-and-source pattern is needed because `crond` runs jobs with a
minimal environment; writing the configuration to a file that each job sources
is simpler than passing environment variables through `crond`'s own `ENVFILE`
mechanism.

---

## `healthcheck`

Checks two conditions:

1. `crond` is running (`pidof` with `pgrep` fallback for portability)
2. The crontab contains a `/backup` entry

Whether the cron job has *run successfully* is not checked: Alpine's `crond`
writes no structured execution log, so there is no lightweight way to detect
the last run time without an external sentinel file.

---

## Adding a new configuration type

1. Add the new type name to the `^(running|startup|backup)$` regex in
   `get-config`.
2. Add a corresponding `get-<type>-config` wrapper if needed for backward
   compatibility.
3. Add test coverage in `test/mokerlink-backup` and `test/staging`.
