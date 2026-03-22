# 1121citrus/mokerlink-backup

A CLI tool to download configuration backups from a [Mokerlink managed network switch](https://www.mokerlink.com/index.php?route=product/product&product_id=396).

## Contents

- [Contents](#contents)
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

## Synopsis

`mokerlink-backup` downloads the running, startup, and/or backup configurations
from a [Mokerlink managed network switch](https://www.mokerlink.com/index.php?route=product/product&product_id=396)
and streams them to stdout as a tar archive or raw text.  The script uses the
[Cisco-inspired CLI](https://www.mokerlink.com/index.php?route=product/product/download&download_id=20)
over SSH.

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

Include only running and startup configs (exclude backup):

```console
mokerlink-backup --host switch -u backup-user -P pw-file --running --startup > partial.tar
```

Include all except startup:

```console
mokerlink-backup --host switch -u backup-user -P pw-file --no-startup > partial.tar
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

Parameter | Option | Environment variable | Default | Notes
--- | --- | --- | --- | ---
Host | `-H`,`--host` | `MOKERLINK_HOST` | `${TAILSCALE_HOST}` | Hostname or IP of the switch. `MOKERLINK_HOST` overrides `TAILSCALE_HOST`.
User | `-u`,`--user` | `MOKERLINK_USER` | `remote-backup` | SSH username.
Password | `-p`,`--password` | `MOKERLINK_PASSWORD` | _none_ | Switch login password. Prefer `--password-file`.
Password file | `-P`,`--password-file` | `MOKERLINK_PASSWORD_FILE` | `/run/secrets/mokerlink-password` | File containing the password. Intended as a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/).
Format | `-f`,`--format` | `MOKERLINK_FORMAT` | `tar` | Output format: `raw` or `tar`.
Tailscale host | — | `TAILSCALE_HOST` | _none_ | Fallback hostname when `MOKERLINK_HOST` is unset.
Debug | — | `DEBUG` | `false` | Set to `true` to enable `xtrace`/`verbose`. **WARNING:** exposes passwords in logs.

### Legacy service parameters

These environment variables are used by the `startup` and `backup` scripts
when the image runs as a Docker Compose service.

Variable | Default | Notes
--- | --- | ---
`AWS_CONFIG_FILE` | `/run/secrets/aws-config` | AWS credentials file. Intended as a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/).
`AWS_DRYRUN` | `false` | Set to `true` to pass `--dryrun` to AWS CLI commands.
`AWS_S3_BUCKET_NAME` | _required_ | S3 bucket for uploads. May include a path prefix, e.g. `your-bucket/backups/daily` (no trailing `/`).
`COMPRESSION` | `none` | Compression algorithm: `bzip`, `bzip2`, `bzip3`, `gz`, `gzip`, `lzma`, `lzo`, `lzop`, `none`, `pigz`, `pixz`, `xz`, `zip`.
`CRON_EXPRESSION` | `@daily` | Standard cron expression. See [crontab.guru](https://crontab.guru/).
`GPG_CIPHER_ALGO` | `aes256` | GnuPG symmetric encryption cipher.
`GPG_PASSPHRASE` | _none_ | GnuPG passphrase. Prefer `GPG_PASSPHRASE_FILE`.
`GPG_PASSPHRASE_FILE` | `/run/secrets/gpg-passphrase` | File containing the GnuPG passphrase. Intended as a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/).
`TZ` | `UTC` | Timezone for cron scheduling, e.g. `America/New_York`.

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
