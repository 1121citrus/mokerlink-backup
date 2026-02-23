# 1121citrus/mokerlink-backup

An application specific service to create [Mokerlink managed network switch](https://www.mokerlink.com/index.php?route=product/product&product_id=396) backups and copy them to S3.

## Contents

- [Contents](#contents)
- [Synopsis](#synopsis)
- [Overview](#overview)
- [Example: backup periodically as cron job](#example-backup-periodically-as-cron-job)
  - [Example Log Output](#example-log-output)
- [Example: Run "One Off" Backup](#example-run-one-off-backup)
- [Example: Fetch running, startup or backup configurations](#example-fetch-running-startup-or-backup-configurations)
- [Example: Docker compose file](#example-docker-compose-file)
- [Configuration](#configuration)
- [Building](#building)

## Synopsis

- Periodically backup the [Mokerlink managed network switch](https://www.mokerlink.com/index.php?route=product/product&product_id=396) to off site storage (S3).
- Backup files are renamed so they sort by date.
- Credentials are supplied by a compose
[secret](https://docs.docker.com/compose/how-tos/use-secrets/).

## Overview

This service will periodically fetch a [Mokerlink managed network switch](https://www.mokerlink.com/index.php?route=product/product&product_id=396) configuration and transfer it to AWS. The script utilizes the [Cisco inspired CLI](https://www.mokerlink.com/index.php?route=product/product/download&download_id=20).

You must separately provision and deploy a user on the Mokerlink managed network switch that will be used to copy perform the backups. The user must be granted `Admin` privileges.

Ensure that firewall rules allow the container to reach the switch's SSH port (22/tcp).

## Example: backup periodically as cron job

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

### Example Log Output

```console
[INFO] 20250922T120714 startup create env file /root/.env
[INFO] 20250922T120714 startup export AWS_CONFIG_FILE='/run/secrets/aws-config'
[INFO] 20250922T120714 startup export AWS_DRYRUN='false'
[INFO] 20250922T120714 startup export AWS_S3_BUCKET_NAME='backups-bucket'
[INFO] 20250922T120714 startup export COMPRESSION='bzip2'
[INFO] 20250922T120714 startup export CRON_EXPRESSION='*/15 * * * *'
[INFO] 20250922T120714 startup export DEBUG='true'
[INFO] 20250922T120714 startup export GPG_CIPHER_ALGO='aes256'
[INFO] 20250922T120714 startup export GPG_PASSPHRASE='**REDACTED**'
[INFO] 20250922T120714 startup export GPG_PASSPHRASE_FILE='/run/secrets/gpg-passphrase'
[INFO] 20250922T120714 startup export MOKERLINK_HOST='switch'
[INFO] 20250922T120714 startup export MOKERLINK_PASSWORD='**REDACTED**'
[INFO] 20250922T120714 startup export MOKERLINK_PASSWORD_FILE='/run/secrets/mokerlink-password'
[INFO] 20250922T120714 startup export MOKERLINK_USER='remote-backup'
[INFO] 20250922T120714 startup export TAILSCALE_HOST=''
[INFO] 20250922T120714 startup export TZ='UTC'
[INFO] 20250922T160714 startup installing cron.d entry: /usr/local/bin/backup
[INFO] 20250922T160714 startup crontab: */15 * * * * /usr/local/bin/backup 2>&1
[INFO] 20250922T160714 startup handing the reins over to cron daemon
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
[INFO] 20250922T161523 backup begin mv '20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg' to S3 bucket 'backups-bucket'
[INFO] 20250922T161523 backup running aws s3 mv --no-progress '20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg' '20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.sha1' s3://backups-bucket/20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg
[INFO] 20250922T161524 backup move: ./20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg to s3://backups-bucket/20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg
[INFO] 20250922T161524 backup move: ./20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.sha1 to s3://backups-bucket/20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.sha1
[INFO] 20250922T161524 backup completed aws s3 mv --no-progress 20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg 20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.sha1 s3://backups-bucket/20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.sha1
[INFO] 20250922T161524 backup finish backup
```

Verify the backup:

```console
$ aws s3 cp s3://backups-bucket/20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.sha1 -
abcb223c64e4b2206a34db069c6bb5ac7949d719  20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar
$ aws s3 cp --quiet s3://backups-bucket/20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg - |  gpg --passphrase-file ../1121-citrus/home-assistant/secrets/gpg-passphrase --decrypt --batch --quiet| bunzip2 | sha1sum
abcb223c64e4b2206a34db069c6bb5ac7949d719  -
$ aws s3 cp --quiet s3://backups-bucket/20250922T161500-switch-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg - |  gpg --passphrase-file ../1121-citrus/home-assistant/secrets/gpg-passphrase --decrypt --batch --quiet| bunzip2 | tar -tf -
./
./20250922T161500-switch-mokerlink-1.0.0.27-running-config-backup.xml
./20250922T161500-switch-mokerlink-1.0.0.27-startup-config-backup.xml
./20250922T161500-switch-mokerlink-1.0.0.27-backup-config-backup.xml
```

## Example: Run "One Off" Backup

Add the `backup` command to the `docker run` command to create a single backup.

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
[INFO] 20250915T013601 backup begin backup
[INFO] 20250915T013601 backup download 'running' configuration from 'switch'
[INFO] 20250915T013604 backup completed download of 'running' configuration from 'switch'
[INFO] 20250915T013604 backup download 'startup' configuration from 'switch'
[INFO] 20250915T013607 backup completed download of 'startup' configuration from 'switch'
[INFO] 20250915T013607 backup download 'backup' configuration from 'switch'
[INFO] 20250915T013610 backup completed download of 'backup' configuration from 'switch'
[INFO] 20250915T013610 backup compressing backup with gzip --best --no-name --quiet --synchronous: 20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.gz
[INFO] 20250915T013610 backup downloaded '20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar' to '20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.gz'
[INFO] 20250915T013610 backup begin mv '20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.gz' to S3 bucket 'backups-bucket'
[INFO] 20250915T013610 backup running aws s3 mv --no-progress '20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.gz' '20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.sha1' s3://backups-bucket/20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.gz
[INFO] 20250915T013611 backup move: ./20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.gz to s3://backups-bucket/20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.gz
[INFO] 20250915T013611 backup move: ./20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.sha1 to s3://backups-bucket/20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.sha1
[INFO] 20250915T013611 backup completed aws s3 mv --no-progress 20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.gz 20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.sha1 s3://backups-bucket/20250915T013601-switch-mokerlink-1.0.0.27-config-backup.tar.sha1
[INFO] 20250915T013611 backup finish backup
```

## Example: Fetch running, startup or backup configurations

Use the `get-running-config`, `get-startup-config` and `get-backup-config` commands to the `docker run` command to fetch a configuration file directly.

```console
$ docker run -i --rm \
         1121citrus/mokerlink-backup \
              get-running-config switch remote-backup my-password 
SYSTEM CONFIG FILE ::= BEGIN
! System Description: KT-NOS POE-G244GSM Switch
! System Version: v1.0.0.27
! System Name: switch
! System Up Time: 0 days, 23 hours, 9 mins, 34 secs
!
!
!
system name "switch"
system location "equipment-rack"
system contact "admin@switch"
ip dhcp
    .
    .
    .
```

The commands take three arguments:

1. `hostname`, defaults to the value of the `MOKERLINK_HOST` or `TAILSCALE_HOST` environment variables, if supplied
1. `username`, defaults to the value of the `MOKERLINK_USER` environment variable or `remote-backup`
1. `password`, defaults to the value of the `MOKERLINK_PASSWORD` or `MOKERLINK_PASSWORD_FILE` environment variable

## Example: Docker compose file

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

## Configuration

Variable | Default | Notes
--- | --- | ---
`AWS_CONFIG_FILE` | `/run/secrets/aws-config` | The externally provided AWS configuration file containing credentials, etc. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`AWS_DRYRUN` | `false` | Set to `true` to pass `--dryrun` to AWS CLI commands.
`AWS_S3_BUCKET_NAME` |  | Required parameter. The backup files will be uploaded to this S3 bucket. You may include slashes after the bucket name if you want to upload into a specific path within the bucket, e.g. `your-bucket-name/backups/daily` (without trailing forward slash (`/`)).
`COMPRESSION` | `none` | Compression application to apply: `bzip`, `bzip2`, `bzip3`, `gz`, `gzip`, `lzma`, `lzo`, `lzop`, `none`, `pigz`, `pixz`, `xz`, `zip`
`CRON_EXPRESSION` | `@daily` | Standard debian-flavored `cron` expression for when the backup should run. Use e.g. `0 4 * * *` to back up at 4 AM every night. See the [man page](http://man7.org/linux/man-pages/man8/cron.8.html) or [crontab.guru](https://crontab.guru/) for more.
`DEBUG` | `false` | Set to `true` to enable `xtrace` and `verbose` shell options.
`GPG_CIPHER_ALGO` | `aes256` | GnuPG symmetric encryption cipher to use to encrypt the backup.
`GPG_PASSPHRASE` | _none_ | GnuPG symmetric encryption pass-phrase to use to encrypt the backup.  WARNING: consider using the more secure `GPG_PASSPHRASE_FILE`, which might be a bind mount or a compose secret.
`GPG_PASSPHRASE_FILE` | `/run/secrets/gpg-passphrase` | A file containing the symmetric encryption pass-phrase to use to encrypt the backup. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`MOKERLINK_HOST` | `${TAILSCALE_HOST}` | Specify the hostname or IP address of the Mokerlink managed network switch. Do not include the final `/`, otherwise backup will fail. Note that the definition of `MOKERLINK_HOST` overrides any `TAILSCALE_HOST` definition.
`MOKERLINK_PASSWORD` | _none_ | The password to unlock the identity file. WARNING: consider using the more secure `MOKERLINK_PASSWORD_FILE`, which might be a bind mount or a compose secret. Note that the definition of `MOKERLINK_PASSWORD` overrides any `MOKERLINK_PASSWORD_FILE` definition.
`MOKERLINK_PASSWORD_FILE` | `/run/secrets/mokerlink-password` | A file containing the password to unlock the identity file. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`MOKERLINK_USER` | `remote-backup` | The username to use to access the Mokerlink managed network switch.
`TAILSCALE_HOST` | _see notes_ | Specify the hostname or IP address of the Mokerlink managed network switch on the Tailscale mesh. Do not include the final `/`, otherwise backup will fail. Used only when `MOKERLINK_HOST` is unset.
`TZ` | `UTC` | Which timezone should `cron` use, e.g. `America/New_York` or `Europe/Warsaw`. See [full list of available time zones](http://manpages.ubuntu.com/manpages/bionic/man3/DateTime::TimeZone::Catalog.3pm.html).

## Building

1. `docker buildx build --sbom=true --provenance=true --provenance=mode=max --platform linux/amd64,linux/arm64 -t 1121citrus/mokerlink-backup:latest -t 1121citrus/mokerlink-backup:x.y.z --push .`
