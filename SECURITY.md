# Security Considerations

This document describes the security model, known limitations, and recommended
hardening steps for `mokerlink-backup`.

## Threat model

The service runs as a scheduled container that:

1. Authenticates to a Mokerlink managed switch over SSH.
2. Downloads three configuration blobs (running, startup, backup).
3. Archives, optionally compresses, and optionally encrypts them.
4. Uploads the archive and a SHA-256 checksum to an S3 bucket.

Trusted components: the container host, the Docker daemon, the S3 bucket
(access-controlled by IAM), and the Tailscale/LAN network path to the switch.

## SSH host key verification

The `get-config` script connects to the switch with:

```text
-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
```

**Implication:** A man-in-the-middle on the network path between the container
and the switch could return a forged configuration.  The switch SSH server does
not provide a way to pre-distribute a known host key in the standard OpenSSH
format, so host-key pinning is not currently feasible.

**Mitigations in place:**

- The container and switch should be on the same trusted LAN segment or
  connected via a Tailscale mesh VPN (both endpoints authenticated by
  WireGuard keys).
- If `TAILSCALE_HOST` is used, the Tailscale ACL controls which nodes may
  initiate connections.
- The backup files themselves are optionally GPG-encrypted at rest in S3, so a
  configuration stolen in transit is the primary residual risk.

**Recommendation:** If the switch SSH server ever begins advertising a stable
host key, modify `get-config` to pass
`-o UserKnownHostsFile=/root/.ssh/known_hosts -o StrictHostKeyChecking=yes`
and mount a `~/.ssh/known_hosts` file into the container (read-only) containing
the switch's host key fingerprint.  This would require a code change.

## Legacy SSH algorithms

The switch firmware requires `ssh-rsa` (SHA-1 based) key exchange.  The
options `-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa`
re-enable this deprecated algorithm.  These options are narrowly scoped to
connections to the switch and do not affect other SSH usage in the container.

## Credential handling

| Credential | Env var (less secure) | File (recommended) | CLI flag |
| --- | --- | --- | --- |
| Switch password | `MOKERLINK_PASSWORD` | `MOKERLINK_PASSWORD_FILE` (default: `/run/secrets/mokerlink-password`) | `--password-file` |
| GPG passphrase | `GPG_PASSPHRASE` | `GPG_PASSPHRASE_FILE` (default: `/run/secrets/gpg-passphrase`) | `--gpg-passphrase-file` |
| AWS credentials | — | `AWS_CONFIG_FILE` (default: `/run/secrets/aws-config`) | `--aws-config` |
| AWS CA bundle | `AWS_CA_BUNDLE` | — | `--aws-certificate` |

**Prefer Docker secrets or read-only bind mounts over environment variables.**
Environment variables are visible in `docker inspect` output, may be captured
by logging infrastructure, and are printed to the `startup` log (redacted, but
the redaction is best-effort).

The switch password is passed to the `expect` subprocess via the
`MOKERLINK_PASSWORD` environment variable rather than as a positional command
argument, to avoid exposure in the process list (`ps aux`).

## DEBUG mode

Setting `DEBUG=true` enables bash `xtrace` (`set -x`), which writes every
expanded command to stderr.  **Do not enable `DEBUG=true` in production.**
Under xtrace the `MOKERLINK_PASSWORD` variable assignment is echoed before the
`get-config` subprocess is spawned, potentially exposing the password in
container logs.

## Integrity verification (SHA-256)

For every backup run the script computes a SHA-256 digest of the uncompressed
`.tar` archive and uploads it alongside the (possibly compressed and encrypted)
backup file:

```text
s3://<bucket>/<timestamp>-<host>-mokerlink-<ver>-config-backup.tar.sha256
s3://<bucket>/<timestamp>-<host>-mokerlink-<ver>-config-backup.tar[.<ext>[.gpg]]
```

The checksum covers the **uncompressed tar** so it can be verified before or
after compression and encryption:

```console
# Decrypt → decompress → hash; compare to the .sha256 file
aws s3 cp --quiet s3://<bucket>/<file>.tar.bz2.gpg - \
  | gpg --passphrase-file /path/to/passphrase --decrypt --batch --quiet \
  | bunzip2 \
  | sha256sum
```

Note: the `.sha256` file is uploaded **unencrypted** even when GPG encryption
is enabled.  This allows integrity verification without the GPG passphrase, but
it also reveals the backup timestamp, switch hostname, and firmware version to
anyone with S3 read access.  Restrict bucket access with IAM policies
accordingly.

## S3 bucket hardening

Recommended S3 bucket configuration:

- **Block Public Access** — enable all four block-public-access settings.
- **Bucket versioning** — enable to retain previous backups and protect against
  accidental overwrites.
- **Server-side encryption** — enable SSE-S3 or SSE-KMS as a defence-in-depth
  measure even when GPG encryption is used.
- **Lifecycle policy** — expire objects after a retention period to limit
  exposure of old configs.
- **Object Lock (WORM)** — optionally enable in governance or compliance mode
  to prevent deletion of recent backups.
- **IAM policy** — grant the container's IAM role only `s3:PutObject` on the
  specific bucket prefix; do not grant `s3:GetObject` or `s3:DeleteObject`.

## Container hardening

- The container runs as the dedicated `mokerlink-backup` user (UID 10001,
  shell `/sbin/nologin`, no login shell).  The crontab is written to
  `/var/spool/cron/crontabs/mokerlink-backup`; supercronic reads it as that user.
- The `~/.gnupg` and `~/.ssh` directories are created with mode `700` and
  `~/.gnupg/pubring.kbx` with mode `600` in the Dockerfile, all owned by
  the service user.
- No ports are exposed; the container initiates all outbound connections.
- The image is built with `--sbom=true --provenance=mode=max` to enable supply
  chain attestation inspection.

## Dependency provenance

The image extends `1121citrus/aws-backup-base` (Amazon Linux 2023, digest-pinned).
Additional packages are installed via `dnf` and Python packages via pip with
minimum version constraints in `requirements.txt`.  The CI pipeline runs
[Trivy](https://github.com/aquasecurity/trivy), Grype, and Docker Scout
vulnerability scans after every build.

Supply chain attestations (SBOM + provenance) are attached to every published
image and can be inspected with:

```console
docker buildx imagetools inspect 1121citrus/mokerlink-backup:<version> \
    --format '{{json .SBOM}}'
docker buildx imagetools inspect 1121citrus/mokerlink-backup:<version> \
    --format '{{json .Provenance}}'
```

## CVE status (last reviewed 2026-07-23)

Advisory scans are run with Grype and Docker Scout in addition to the gating
Trivy scan.

### Trivy (gating scan)

| Result | Notes |
| --- | --- |
| **0 vulnerabilities** | Gating scan passes; build is not blocked. |

### Open vulnerabilities

| CVE | Component | Severity | Status |
| --- | --- | --- | --- |
| CVE-2026-44431 | urllib3 (pip), currently pinned `>=2.6.3` | HIGH | Fix version 2.7.0 not yet published on PyPI; suppressed in `.trivyignore` pending upstream release |
| CVE-2026-44432 | urllib3 (pip), currently pinned `>=2.6.3` | HIGH | Same as above |
| CVE-2026-58010 – CVE-2026-58016 | glib2 (AL2023, inherited from `aws-backup-base`) | HIGH | Fix `2.82.2-770.amzn2023` not yet in the AL2023 repos |
| CVE-2026-54369, CVE-2026-54370 | libacl (AL2023, inherited from `aws-backup-base`) | HIGH | Fix `2.4.0-1.amzn2023.0.1` not yet in the AL2023 repos |
| CVE-2026-0864, CVE-2026-11940, CVE-2026-11972, CVE-2026-3276, CVE-2026-9669 | python3 / python3-libs (AL2023, inherited from `aws-backup-base`) | HIGH | Fix `3.9.25-1.amzn2023.0.8` not yet in the AL2023 repos |

The urllib3 pair are information-disclosure/DoS issues in its redirect and
decompression handling. `pip3 install 'urllib3>=2.7.0'` fails outright in CI
(no matching distribution — highest available is 2.6.3), so the fix cannot be
applied yet. Tracked upstream: <https://pypi.org/project/urllib3/#history>.
Remove the `.trivyignore` suppression and bump the Dockerfile's `urllib3`
floor as soon as 2.7.0 is published.

The AL2023 batch (glib2/libacl/python3) is already documented and suppressed
in `aws-backup-base`'s own `.trivyignore`/`SECURITY.md` (reviewed 2026-07-21);
since Trivy suppression is a scan-time parameter rather than something baked
into the image, this repo's own `.trivyignore` needed the same entries added
separately. Remove them here once `aws-backup-base` reports these fixed.

The migration to Amazon Linux 2023 (v1.0.1, 2026-04-27) resolved all
previously documented Alpine-specific CVEs. CI runs Trivy, Grype, and Docker
Scout on every push; any new findings will be tracked here.

### Remediated vulnerabilities

| CVE / Advisory | Component | Remediation |
| --- | --- | --- |
| Alpine APK CVEs (multiple) | `python3`, `busybox`, `openssh`, `unzip`, `py3-urllib3`, `py3-cryptography`, `py3-pip` | Resolved by migrating base image from Alpine 3.22 to AL2023 (v1.0.1) |
| CVE-2026-32280 — CVE-2026-33810 | supercronic Go stdlib | Resolved: `aws-backup-base` now ships supercronic v0.2.45 (Go ≥1.26.2) |
| GHSA-r6ph-v2qm-q3c2, CVE-2026-26007 | cryptography (pip) | Pinned `cryptography>=47.0.0` in `requirements.txt` |
| GHSA-gm62-xv2j-4w53 + 3 others | urllib3 (pip) | Pinned `urllib3>=2.6.3` in `requirements.txt` |
| GHSA-8rrh-rw8j-w5fx, CVE-2026-24049 | wheel (pip) | Pinned `wheel>=0.47.0` in `requirements.txt` |
| GHSA-58pv-8j8x-9vj2 | jaraco.context (pip) | Pinned `jaraco-context>=6.1.2` in `requirements.txt` |
| GHSA-4xh5-x5gv-qwph, CVE-2025-8869 | pip | Upgraded to pip≥25.3 (via `aws-backup-base`) |
| GHSA-jfmj-5v4g-7637, CVE-2024-5569 | zipp (pip) | Pinned `zipp>=3.23.1` in `requirements.txt` |

### Test suite status

All 103 unit tests pass after the Dockerfile changes above.  The staging
integration test (`test/staging`) requires a live Mokerlink switch and live AWS
credentials; it is intentionally skipped in automated CI and must be run
manually in a network-connected environment.

## Reporting vulnerabilities

Please report security vulnerabilities through the [GitHub Security tab](https://github.com/1121citrus/mokerlink-backup/security).
Do not open a public GitHub issue for security vulnerabilities.
