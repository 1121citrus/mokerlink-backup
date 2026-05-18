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

## CVE status (last reviewed 2026-05-17)

Three scanners run on every build:

| Scanner | Role | Blocks build? |
| --- | --- | --- |
| Trivy | Gating (`--exit-code 1 --ignore-unfixed --severity HIGH,CRITICAL`) | Yes |
| Grype | Advisory (full severity, informational output) | No |
| Docker Scout | Advisory (full severity, informational output) | No |

### Trivy (gating scan)

| Result | Notes |
| --- | --- |
| **0 vulnerabilities** | All findings are either absent, unfixed upstream (suppressed by `--ignore-unfixed`), or explicitly accepted in `.trivyignore`. |

### Open vulnerabilities — accepted and documented

The entries below appear in Grype and/or Scout but cannot be fixed at this time.
Each one is logged in `.trivyignore` with a rationale comment.

#### urllib3 — RPM version 1.25.10 (system package)

The AL2023 RPM `python3-urllib3-1.25.10` coexists with the pip-installed
`urllib3-2.6.3`. Python scripts use the pip version (higher path priority); the
RPM is present only to satisfy system-package metadata. No RPM upgrade is
available in the AL2023 repository.

| CVE | Severity | Description | Fix version |
| --- | --- | --- | --- |
| CVE-2021-33503 | HIGH | Uncontrolled resource consumption | 1.26.5 (no RPM fix) |
| CVE-2023-43804 | HIGH | Sensitive info exposure via cookie headers | 1.26.17 (no RPM fix) |
| CVE-2025-66418 | HIGH | Allocation without limits (amplification) | 2.6.0 (no RPM fix) |
| CVE-2025-66471 | HIGH | Data amplification | 2.6.0 (no RPM fix) |
| CVE-2026-21441 | HIGH | Data amplification | 2.6.3 (no RPM fix) |
| CVE-2026-44431 | HIGH | Sensitive info exposure | 2.7.0 (no RPM fix) |

#### urllib3 — pip version 2.6.3

| CVE | Severity | Description | Fix version | Status |
| --- | --- | --- | --- | --- |
| CVE-2026-44431 | HIGH | Sensitive info exposure | 2.7.0 | urllib3 2.7.0 not installable with pip 21.3.1 in AL2023 |
| CVE-2026-44432 | HIGH | Data amplification | 2.7.0 | Same — awaiting compatible pip/package release |

#### python3-pip — RPM version 21.3.1-2.amzn2023.0.16

| CVE | Severity | Description | Fix version | Status |
| --- | --- | --- | --- | --- |
| CVE-2026-6357 | HIGH | Arbitrary code execution | 21.3.1-2.amzn2023.0.19 | Fix identified; not yet available in the AL2023 dnf repository |

#### AL2023 OS packages — fix versions identified but not yet in repo

These packages have known fix versions in the ALAS advisory database but the
patched packages are not yet available via `dnf` in the AL2023 repository used
by this image's base layer. All are suppressed in `.trivyignore`.

| CVE | Severity | Component | Fix version |
| --- | --- | --- | --- |
| CVE-2026-4046 | HIGH | `glibc` | 2.34-231.amzn2023.0.4 |
| CVE-2026-35385 | HIGH | `openssh`, `openssh-clients` | 8.7p1-8.amzn2023.0.17 |
| CVE-2026-3644 | HIGH | `python3`, `python3-libs` | 3.9.25-1.amzn2023.0.5 |
| CVE-2026-4786 | HIGH | `python3`, `python3-libs` | 3.9.25-1.amzn2023.0.5 |
| CVE-2026-6100 | HIGH | `python3`, `python3-libs` | 3.9.25-1.amzn2023.0.5 |

#### supercronic — Go stdlib vulnerabilities (inherited from base image)

`supercronic` is a statically-linked binary compiled with Go 1.26.2 and
embedded in the `aws-backup-base` image. These CVEs require rebuilding
supercronic with Go ≥1.26.3. They cannot be patched by changes to this
Dockerfile. All are suppressed in `.trivyignore`.

| CVE | Severity | Description |
| --- | --- | --- |
| CVE-2026-32280 — CVE-2026-33810 | HIGH | Go stdlib batch (previously documented) |
| CVE-2026-33811 | HIGH | `LookupCNAME` cgo DNS resolver issue |
| CVE-2026-33814 | HIGH | HTTP/2 SETTINGS frame processing DoS |
| CVE-2026-39820 | HIGH | `ParseAddress`/`ParseAddressList` input handling |
| CVE-2026-39836 | HIGH | `Dial`/`LookupPort` panic on NUL byte |
| CVE-2026-42499 | HIGH | `consumePhrase` DoS via pathological input |
| CVE-2026-42501 | HIGH | Go stdlib issue (Go ≥1.26.3 required) |

Tracked: <https://github.com/aptible/supercronic/releases>

#### perl — legacy CVEs (advisory scanners only)

`perl` is pulled in as a transitive dnf dependency. These CVEs appear in Grype
and Scout but Trivy does not flag them (no unfixed annotation in the AL2023 DB).
A `dnf update perl` would install the patched version if it becomes available.

| CVE | Severity | Fix version |
| --- | --- | --- |
| CVE-2023-31484 | HIGH | 5.32.1-477.amzn2023.0.4 |
| CVE-2023-31486 | HIGH | 5.32.1-477.amzn2023.0.5 |

### Remediated vulnerabilities

| CVE / Advisory | Component | Remediation |
| --- | --- | --- |
| Alpine APK CVEs (multiple) | `python3`, `busybox`, `openssh`, `unzip`, `py3-urllib3`, `py3-cryptography`, `py3-pip` | Resolved by migrating base image from Alpine 3.22 to AL2023 (v1.0.1) |
| CVE-2026-32280 — CVE-2026-33810 | supercronic Go stdlib | Partially resolved: `aws-backup-base` ships supercronic v0.2.45 (Go ≥1.26.2); newer batch of Go stdlib CVEs (33811, 33814, 39820, 39836, 42499, 42501) added to `.trivyignore` pending Go ≥1.26.3 release |
| GHSA-r6ph-v2qm-q3c2, CVE-2026-26007 | cryptography (pip) | Pinned `cryptography>=46.0.5` in Dockerfile |
| GHSA-gm62-xv2j-4w53 + 3 others | urllib3 (pip) | Pinned `urllib3>=2.6.3` in Dockerfile |
| GHSA-8rrh-rw8j-w5fx, CVE-2026-24049 | wheel (pip) | Pinned `wheel>=0.46.2` in Dockerfile |
| GHSA-58pv-8j8x-9vj2 | jaraco.context (pip) | Pinned `jaraco.context>=6.1.0` in Dockerfile |
| GHSA-4xh5-x5gv-qwph, CVE-2025-8869 | pip | Upgraded to pip≥25.3 (via `aws-backup-base`) |
| GHSA-jfmj-5v4g-7637, CVE-2024-5569 | zipp (pip) | Pinned `zipp>=3.19.1` in Dockerfile |
| CVE-2022-40897, CVE-2024-6345, CVE-2025-47273 | setuptools | Installed `setuptools>=78.1.1` via pip `--ignore-installed` to override RPM 59.6.0 |

### Test suite status

All unit tests pass. The staging integration test (`test/staging`) requires a
live Mokerlink switch and live AWS credentials; it is intentionally skipped in
automated CI and must be run manually in a network-connected environment.

## Reporting vulnerabilities

Please report security vulnerabilities through the [GitHub Security tab](https://github.com/1121citrus/mokerlink-backup/security).
Do not open a public GitHub issue for security vulnerabilities.
