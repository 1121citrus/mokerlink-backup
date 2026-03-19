# Testing

## Overview

The test suite is split into two tiers:

| Tier | Scripts | Requires | Run by |
|---|---|---|---|
| Automated | `run-all` and its constituent scripts | Docker only | `./build` |
| Manual integration | `staging` | Live switch + credentials | Developer |

---

## Automated tests (`test/run-all`)

`run-all` is the CI-suitable suite.  It is invoked automatically by `./build`
during stage 3 and requires nothing beyond a local Docker daemon.  All switch
interaction is replaced by the stub at `test/bin/get-config`.

### Constituent test scripts

| Script | What it tests |
|---|---|
| `mokerlink-backup` | CLI option parsing, flag validation, tar/raw output format, config selection flags (`-r`, `-s`, `-b`, `--no-*`) |
| `backup-required-vars` | `backup` script rejects missing `AWS_S3_BUCKET_NAME`, `MOKERLINK_HOST`, and password; accepts `TAILSCALE_HOST` fallback and password file |
| `backup-success` | `backup` script succeeds for each supported compression algorithm; tar archive contains all three config files |
| `backup-encryption` | GPG encryption is applied when a passphrase is available; skipped when none is |
| `healthcheck` | `healthcheck` exits non-zero when `crond` is absent or crontab is missing; exits zero when both are present |

### Running

```console
# Via the build script (recommended — also lints, builds, and scans)
./build --no-scan

# Directly, against a specific image
IMAGE=1121citrus/mokerlink-backup:dev-abc1234 test/run-all
```

The `IMAGE` environment variable selects which image to test.  When omitted,
`test/run-all` defaults to `1121citrus/mokerlink-backup:latest`.  `./build`
always sets `IMAGE` to the image it just built, so the correct image is tested
automatically.

### Test stubs (`test/bin/`)

| Stub | Replaces | Behavior |
|---|---|---|
| `get-config` | `src/bin/get-config` | Emits two header lines (`! System Version: v1.2.3`, `! System Name: test-switch`) without opening an SSH connection |
| `aws` | AWS CLI | Copies the backup file to `/output` if that path is mounted; otherwise no-ops |

---

## Manual integration tests (`test/staging`)

`test/staging` exercises the full end-to-end CLI path with a real Mokerlink
switch and real credentials.  It is **not** part of `run-all` and is never
run in CI.

Run it manually before tagging a release, from a host that can reach the
switch (local network or Tailscale).

### Required environment

| Variable | Required for | Notes |
|---|---|---|
| `IMAGE` | All tests | Image to test; defaults to `1121citrus/mokerlink-backup:latest` |
| `MOKERLINK_HOST` | Switch-dependent tests | Hostname or IP of the switch; omit to run only switch-independent tests |
| `MOKERLINK_USER` | Switch-dependent tests | SSH username; defaults to `remote-backup` |
| `MOKERLINK_PASSWORD` | Switch-dependent tests | Switch password; alternatively set `MOKERLINK_PASSWORD_FILE` |
| `MOKERLINK_PASSWORD_FILE` | Switch-dependent tests | Path to a file containing the password; read once at startup |

### Running

```console
# Switch-independent tests only (help, version, option validation)
IMAGE=1121citrus/mokerlink-backup:1.2.3 test/staging

# Full suite against a live switch
IMAGE=1121citrus/mokerlink-backup:1.2.3 \
  MOKERLINK_HOST=10.0.0.1 \
  MOKERLINK_PASSWORD=secret \
  test/staging

# Using a password file
IMAGE=1121citrus/mokerlink-backup:1.2.3 \
  MOKERLINK_HOST=10.0.0.1 \
  MOKERLINK_PASSWORD_FILE=./secrets/mokerlink-password \
  test/staging
```

Tests that require the switch print `SKIP` (not `FAIL`) when `MOKERLINK_HOST`
or a password is absent, so the script always exits cleanly in a
credentials-free environment.

### What is tested

| Test | Switch required |
|---|---|
| `--help` exits 0 and prints usage | no |
| `--version` exits 0 and prints a non-empty string | no |
| Unknown option exits non-zero | no |
| Invalid `--format` value exits non-zero | no |
| All configs excluded exits non-zero | no |
| Default output is a valid tar with all three config files | yes |
| `-r` / `--running` produces tar with only the running config | yes |
| `-s` / `--startup` produces tar with only the startup config | yes |
| `-b` / `--backup` produces tar with only the backup config | yes |
| `--no-running` produces tar without the running config | yes |
| `--running --format raw` outputs text containing `! System Version:` | yes |
| `MOKERLINK_BACKUP_NAME_FILE` is written with a `*-config-backup.tar` filename | yes |
