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

## CVE status (last reviewed 2026-11-15)

Three scanners run on every build. The posture below reflects the pinned
`aws-backup-base` 1.2.2 digest
`sha256:280e9ec4a1996b6bf7720ceed9add0f7fcd619b99b840e06869cf81bb58dfae0`.

| Scanner | Role | Blocks build? |
| --- | --- | --- |
| Trivy | Gating (`--exit-code 1 --ignore-unfixed --severity HIGH,CRITICAL`) | Yes |
| Grype | Full severity, informational output (no `fail-on-severity`) | No |
| Docker Scout | Gating (`--exit-code --only-severity critical,high`), added by the generator regeneration in `f0dc9e9` | Yes |

### Trivy (gating scan)

| Result | Notes |
| --- | --- |
| **0 vulnerabilities** | Passes after `.trivyignore` suppression of the four pip `urllib3` entries below. Without suppression, those four are the only HIGH/CRITICAL findings (verified 2026-11-15). |

### Docker Scout (gating scan) — currently failing

As of 2026-11-15 Scout reports 60 HIGH findings, none of which has an
installable fix (details in the sections below):

- 46 against `perl-*` subpackages (`CVE-2023-31484`, `CVE-2023-31486`):
  false positives, see "perl" below.
- 7 against the RPM `urllib3` 1.25.10 and 3 against the RPM `setuptools`
  59.6.0: no AL2023 RPM fix, and both RPMs are required by `awscli-2`.
- 4 against the pip `urllib3` 2.6.3: the fix needs Python >= 3.10.

Scout has no repository-local suppression file that `build` reads (unlike
`.trivyignore` for Trivy), so the build exits non-zero at Stage 4c until
either a VEX/exception mechanism is added to the generated `build` or the
base image moves to Python >= 3.10.

### Open vulnerabilities — accepted and documented

The entries below cannot be fixed at this time.

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
| CVE-2026-97687 | HIGH | HTTPS-proxy TLS configuration override | 2.8.0 (no RPM fix) |
| CVE-2026-97689 | HIGH | Unbounded memory allocation in chunk parser | 2.8.0 (no RPM fix) |

`awscli-2` 2.38.0 requires `python3.9dist(urllib3) <= 2.6.3`, so the RPM
cannot be removed or replaced. No newer RPM exists even with
`dnf --releasever=latest` (checked 2026-11-15).

#### urllib3 — pip version 2.6.3

`urllib3` 2.7.0 and 2.8.0 both declare `requires_python: ">=3.10"` (PyPI
metadata, verified 2026-11-15); the base image ships Python 3.9. All four
are suppressed in `.trivyignore`.

| CVE | Severity | Description | Fix version | Status |
| --- | --- | --- | --- | --- |
| CVE-2026-44431 | HIGH | Sensitive info exposure | 2.7.0 | Requires Python >= 3.10 |
| CVE-2026-44432 | HIGH | Data amplification | 2.7.0 | Requires Python >= 3.10 |
| CVE-2026-97687 | HIGH | HTTPS-proxy TLS configuration override | 2.8.0 | Requires Python >= 3.10; suppressed 2026-11-15. The image uses no HTTPS proxy |
| CVE-2026-97689 | HIGH | Unbounded memory allocation in chunk parser | 2.8.0 | Requires Python >= 3.10; suppressed 2026-11-15 |

#### setuptools — RPM version 59.6.0 (system package)

Scout reports `CVE-2022-40897`, `CVE-2024-6345`, and `CVE-2025-47273` (HIGH)
against the RPM copy. `python3-setuptools` is required by
`python3-ruamel-yaml` and `python3-distro` (both `awscli-2` dependencies);
no AL2023 RPM fix exists. The pip copy under `/usr/local` (`setuptools`
>= 78.1.1) is not affected.

#### supercronic — Go stdlib (inherited from base image)

`aws-backup-base` 1.2.2 builds `supercronic` v0.2.49 with Go 1.27.3; Trivy
reports no findings. Grype reports `GO-2026-6859` (severity unknown, fixed
in Go 1.27.4); it clears when `aws-backup-base` is rebuilt.

#### perl — false positives (Scout only)

`perl` is inherited from `aws-backup-base`. Scout compares each `perl-*`
subpackage's own version (for example `perl-base` `2.27-477.amzn2023.0.11`)
against the `perl` source-package fix (`5.32.1-477.amzn2023.0.4` / `.0.5`).
The installed release `477.amzn2023.0.11` is already newer than both.

| CVE | Severity | Fix version |
| --- | --- | --- |
| CVE-2023-31484 | HIGH | 5.32.1-477.amzn2023.0.4 |
| CVE-2023-31486 | HIGH | 5.32.1-477.amzn2023.0.5 |

### Resolved 2026-11-15

`dnf install`/`upgrade`/`reinstall` now run with `--releasever=latest`, and
the base image is pinned by digest (`aws-backup-base` 1.2.2) instead of
`:latest`. This cleared 55 gating Trivy HIGH findings in AL2023 packages
without suppression (`curl-minimal`/`libcurl-minimal`, `cyrus-sasl-lib`,
`glibc`, `libcap`, `pcre2`, `python3`/`python3-libs`, `rpm`, `sqlite-libs`,
and related subpackages). Every earlier AL2023 OS-package, `python3-pip`
RPM, and `supercronic` Go stdlib suppression was removed from
`.trivyignore`: the installed packages and binary now contain the fixes.

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
