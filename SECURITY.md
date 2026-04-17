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

| Credential | Env var (less secure) | File (recommended) |
| --- | --- | --- |
| Switch password | `MOKERLINK_PASSWORD` | `MOKERLINK_PASSWORD_FILE` (default: `/run/secrets/mokerlink-password`) |
| GPG passphrase | `GPG_PASSPHRASE` | `GPG_PASSPHRASE_FILE` (default: `/run/secrets/gpg-passphrase`) |
| AWS credentials | — | `AWS_CONFIG_FILE` (default: `/run/secrets/aws-config`) |

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
  `/var/spool/cron/crontabs/mokerlink-backup`; `crond` reads it as that user.
- The `~/.gnupg` and `~/.ssh` directories are created with mode `700` and
  `~/.gnupg/pubring.kbx` with mode `600` in the Dockerfile, all owned by
  the service user.
- No ports are exposed; the container initiates all outbound connections.
- The image is built with `--sbom=true --provenance=mode=max` to enable supply
  chain attestation inspection.

## Dependency provenance

The Docker image is built on `alpine:3.22` (official Docker Hub image).  All
packages are installed from the Alpine package index pinned to version
constraints in the `Dockerfile`.  The CI pipeline runs a
[Trivy](https://github.com/aquasecurity/trivy) vulnerability scan after every
build and fails on unfixed CVEs.

Two Python packages (`cryptography` and `urllib3`) are upgraded beyond the
Alpine-packaged versions via pip in the Dockerfile build layer.  This is
necessary because Alpine 3.22 does not yet carry patched `py3-cryptography` or
`py3-urllib3` apk packages for the CVEs listed below.

Supply chain attestations (SBOM + provenance) are attached to every published
image and can be inspected with:

```console
docker buildx imagetools inspect 1121citrus/mokerlink-backup:<version> \
    --format '{{json .SBOM}}'
docker buildx imagetools inspect 1121citrus/mokerlink-backup:<version> \
    --format '{{json .Provenance}}'
```

## CVE status (last reviewed 2026-04-17)

Advisory scans are run with Grype and Docker Scout in addition to the gating
Trivy scan.  The tables below reflect the state as of the last `build --advise
all` run.

### Trivy (gating scan)

| Result | Notes |
| --- | --- |
| **0 vulnerabilities** | Gating scan passes; build is not blocked. |

### Fixed by Dockerfile pip upgrade

The following CVEs were remediated by pip-installing patched versions over the
Alpine-packaged versions (or pip's own bundled dependencies).
The pip step runs in the same `RUN` layer as the `apk add` installs.

| Package | Installed (apk/pip) | Fixed (pip) | CVEs / GHSAs | Severity |
| --- | --- | --- | --- | --- |
| `cryptography` | 44.0.3-r0 | ≥ 46.0.5 | GHSA-r6ph-v2qm-q3c2, CVE-2026-26007 | High |
| `urllib3` | 1.26.20-r1 | ≥ 2.6.3 | GHSA-gm62-xv2j-4w53, GHSA-38jv-5279-wg99, GHSA-2xpw-w6gg-jr37, CVE-2026-21441, CVE-2025-66471, CVE-2025-66418 | High |
| `wheel` | 0.45.1 (pip dep) | ≥ 0.46.2 | GHSA-8rrh-rw8j-w5fx, CVE-2026-24049 | High |
| `jaraco.context` | 5.3.0 (pip dep) | ≥ 6.1.0 | GHSA-58pv-8j8x-9vj2 | High |
| `pip` | 25.1.1-r0 | ≥ 25.3 | GHSA-4xh5-x5gv-qwph, CVE-2025-8869 | Medium |
| `zipp` | 3.17.0 (pip dep) | ≥ 3.19.1 | GHSA-jfmj-5v4g-7637, CVE-2024-5569 | Medium |

Trivy (the gating scanner) confirms **0 vulnerabilities** for all pip-managed
Python packages after the upgrade step.

### Unfixed — no patch available in Alpine 3.22

The following findings have no available fix in the Alpine package index.  They
are tracked here and will be re-evaluated when Alpine releases patched packages.
None of these affect the image's primary threat surface (see Threat model above).

| Package | Version | CVE | Severity | Notes |
| --- | --- | --- | --- | --- |
| `python3` | 3.12.13-r0 | CVE-2025-13836 | High | No Alpine fix available |
| `unzip` | 6.0-r15 | CVE-2008-0888 | High | No Alpine fix; unzip is used only by `zip` compression path, not network-facing |
| `py3-urllib3` (apk) | 1.26.20-r1 | CVE-2025-66471, CVE-2025-66418 | High | Alpine apk package superseded by pip-installed 2.6.3; advisory scanners may still flag the apk metadata entry |
| `py3-cryptography` (apk) | 44.0.3-r0 | CVE-2026-26007 | High | Alpine apk package superseded by pip-installed ≥ 46.0.5; advisory scanners may still flag the apk metadata entry |
| `py3-pip` (apk) | 25.1.1-r0 | CVE-2025-8869, CVE-2026-1703 | Med/Low | Alpine apk entry for pip superseded by pip-installed 26.x; advisory scanners may still flag the apk metadata entry |
| `wheel` (pip-vendored) | 0.45.1 | GHSA-8rrh-rw8j-w5fx | High | pip internally vendors a copy of wheel for bootstrap purposes; this is distinct from the standalone `wheel` package (upgraded to 0.46.3). The vendored copy lives inside pip's own source tree and cannot be upgraded externally. Trivy confirms 0 vulns for the standalone installed package. |
| `jaraco.context` (pip-vendored) | 5.3.0 | GHSA-58pv-8j8x-9vj2 | High | pip internally vendors a copy of `jaraco.context`; this is distinct from the standalone package (upgraded to 6.1.2). Cannot be upgraded externally. Trivy confirms 0 vulns for the standalone installed package. |
| `busybox` | 1.37.0-r20 | CVE-2025-60876 | Medium | No Alpine fix available |
| `openssh` | 10.0_p1-r10 | CVE-2026-35414 | Medium | No Alpine fix available |
| `openldap` | 2.6.8-r0 | CVE-2026-22185 | Medium | No Alpine fix; openldap is a transitive dependency |
| `gnupg` (and sub-packages) | 2.4.9-r0 | CVE-2022-3219 | Low | No Alpine fix |
| `lz4` | 1.10.0-r0 | CVE-2025-62813 | Unspecified | No Alpine fix; lz4 is a transitive dependency |

### False positives noted

| Package | Version | CVE | Tool | Reason |
| --- | --- | --- | --- | --- |
| `py3-jmespath` | 1.0.1-r4 | CVE-2022-32511 | Grype | CVE-2022-32511 was fixed in jmespath 1.0.1; the installed version (1.0.1-r4) is at or above the fix version — Grype does not record a `fixed-in` entry, indicating a stale or incorrect database entry |

### Test suite status

All 78 unit tests pass after the Dockerfile changes above.  The staging
integration test (`test/staging`) requires a live Mokerlink switch and live AWS
credentials; it is intentionally skipped in automated CI and must be run
manually in a network-connected environment.

## Reporting vulnerabilities

Please report security vulnerabilities through the [GitHub Security tab](https://github.com/1121citrus/mokerlink-backup/security).
Do not open a public GitHub issue for security vulnerabilities.
