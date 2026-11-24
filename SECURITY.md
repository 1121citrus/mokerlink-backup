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

## CVE status (last reviewed 2026-11-24)

Three scanners run on every build. The posture below reflects the pinned
`aws-backup-base` 1.2.3 digest
`sha256:dc4c176e47b9d1b818c149466bcb61ed2e5ea643a0d947d6b8fc8519b2b14852`.

| Scanner | Role | Blocks build? |
| --- | --- | --- |
| Trivy | Gating (`--exit-code 1 --ignore-unfixed --severity HIGH,CRITICAL`) | Yes |
| Grype | Full severity, informational output (no `fail-on-severity`) | No |
| Docker Scout | Gating, filtered against `.scoutignore` before failing (see below) | Only on an unreviewed finding |

### Trivy (gating scan)

| Result | Notes |
| --- | --- |
| **0 vulnerabilities** | Passes after `.trivyignore` suppression of the four pip `urllib3` entries below. Without suppression, those four are the only HIGH/CRITICAL findings (verified 2026-11-15). |

### Docker Scout (gating scan) — passes via two mechanisms

Scout has no single native repository-local ignorefile like Trivy's
`.trivyignore` or Grype's `.grype.yaml`. Two separate mechanisms now
stand in for one, deliberately kept distinct because they mean different
things:

1. **`.scout.vex.json`** (an OpenVEX document, loaded via
   `--vex-location` / `--vex-author "1121 Citrus Avenue"`) — for findings
   that are **verified false positives**: the vulnerability does not
   actually apply. It currently covers only the two `perl-*` CVEs below
   (46 of Scout's 60 original HIGH findings), verified by rerunning the
   exact Stage 4c command before and after adding it. The product scope
   is the bare image name (`pkg:docker/1121citrus/mokerlink-backup`, no
   `@version`/tag) rather than an image+tag pair, confirmed by testing
   both forms directly against this image: a tagged purl (e.g.
   `@dev-7bd363f`) only matches that exact tag, while the bare form
   matches every tag. `VERSION` changes on every build
   (`dev-<short-sha>`), so a tag-scoped statement would need editing on
   every commit; the bare form is the only one that stays valid without
   touching the file again.
2. **`.scoutignore`** (plain CVE/GHSA ids, one per line, `.trivyignore`
   style) — for findings that are **genuinely present but reviewed and
   accepted** as currently unfixable. `build` Stage 4c greps its own
   captured Scout output for `✗ HIGH`/`✗ CRITICAL` CVE ids and only sets
   the deferred gate failure (see below) if one of them is *not* in this
   list; Scout's own `--exit-code` status is otherwise ignored. This
   exists because OpenVEX's `not_affected` status is semantically
   "doesn't apply" — using it for "applies, but we accept the risk"
   would make the VEX document itself a false statement about the
   image, which is worse than a failing build.

Current breakdown, verified 2026-11-24:

- 46 findings against `perl-*` subpackages (`CVE-2023-31484`,
  `CVE-2023-31486`): false positives, see "perl" below —
  **suppressed via `.scout.vex.json`**.
- 7 against the RPM `urllib3` 1.25.10, 4 against the pip `urllib3`
  2.6.3 (some CVE ids shared between the two), and 3 against the RPM
  `setuptools` 59.6.0: no AL2023 RPM fix for either RPM, and the pip
  `urllib3` fix needs Python >= 3.10 — all 12 unique ids **listed in
  `.scoutignore`**, not suppressed from the report, but no longer
  failing the build.

Any *other* HIGH/CRITICAL finding Scout reports — a new CVE against an
existing package, or any finding against a package not covered here —
is not on either list and still fails Stage 4c and the build, exactly as
before. Review `.scoutignore` whenever `aws-backup-base` is bumped or
AL2023 ships a newer `python3-urllib3`/`python3-setuptools` build: the
fix may exist upstream even though the entry is still sitting there.

#### `build` no longer aborts on a gating-scan failure

Before 2026-11-24, a failing Trivy or Scout exit code propagated straight
through `set -euo pipefail` (Trivy) or an explicit `exit` (Scout),
terminating the script immediately — skipping Grype, every later
advisory stage (Dive, Coverage, Metrics, Churn), and giving no way to see
their output on a run that also happens to fail the gate. `build` now
records a failing Trivy status, or a Scout status with at least one
unreviewed finding, in `_gate_failed`/`_gate_exit` instead of exiting
there: Grype and every advisory stage still run, Stage 6 Push still
refuses to run (checked explicitly, since it would otherwise be
unguarded), and the script still exits with the original gating status
code at the very end. With `.scout.vex.json` and `.scoutignore` both in
place, a normal build no longer reaches this path via Scout at all — it
now exists for a genuinely new, unreviewed finding, or for Trivy, which
has no accepted findings to review as of this writing.

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
>= 82.0.1) is not affected by these three.

#### setuptools — both copies, Medium/Low (Grype only)

Grype additionally reports two findings against *both* the RPM
(59.6.0) and pip (82.0.1) copies, verified 2026-11-24:

| CVE / Advisory | Severity | Fixed version | Status |
| --- | --- | --- | --- |
| GHSA-h35f-9h28-mq5c | Medium | 83.0.0 | Requires Python >= 3.10 |
| GHSA-xmj3-9gf7-h52w | Low | 84.1.0 | Requires Python >= 3.10 |

82.0.1 is the newest `setuptools` release whose PyPI metadata permits
Python 3.9 (verified 2026-11-24 by attempting `pip install setuptools` on
the base image's interpreter: 82.0.1 resolves, 83.0.0/84.1.0 do not). The
RPM has no newer AL2023 build either (`dnf list --showduplicates
python3-setuptools` tops out at 59.6.0-2.amzn2023.0.6). Both suppressed in
`.grype.yaml`; not reported by Trivy (below its HIGH/CRITICAL gate) or the
`.trivyignore` suppression list.

#### supercronic — Go stdlib (inherited from base image)

`aws-backup-base` 1.2.3 builds `supercronic` v0.2.49 with Go 1.27.4,
resolving the 10 Go `stdlib` findings reported against the 1.2.2-pinned
Go 1.27.3 build: 8 HIGH (`CVE-2026-97033` through `-97039`, `-97043`) and
2 Medium (`CVE-2026-97054`, `GO-2026-6859`). See "Resolved 2026-11-24"
below.

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

### Resolved 2026-11-24

Two independent fixes, verified with an unsuppressed `grype
docker-archive:...` scan before and after (23 findings → 10):

- Bumped `BASE_IMAGE` from `aws-backup-base` 1.2.2 to 1.2.3
  (`sha256:dc4c176e47b9d1b818c149466bcb61ed2e5ea643a0d947d6b8fc8519b2b14852`).
  1.2.3 builds `supercronic` with Go 1.27.4 instead of 1.27.3, resolving
  all 10 Go `stdlib` findings described under "supercronic" above, and
  excludes the `python3-pygments` RPM (an unused optional dependency of
  `python3-prompt-toolkit`), resolving Medium `GHSA-mrwq-x4v8-fh7p`
  (pygments 2.7.4 → needs 2.15.0).
- Added `dnf remove -y python3-pip` to the end of the Dockerfile's `RUN`
  instruction, after every `pip3 install` step that needs it. Nothing in
  `src/` or `test/` invokes `pip`/`pip3` at runtime — it is a build-time
  tool only — and `dnf remove`'s dry run
  (`dnf remove -y --assumeno python3-pip`) confirmed it has no reverse
  dependencies in this image, so removing it does not cascade into
  removing `python3-setuptools`, `python3-urllib3`, or any other RPM.
  This resolves the Medium `pip` 21.3.1 findings `GHSA-qwm4-qh6w-59xr`
  and `GHSA-58qw-9mgm-455v` (both require pip >= 26.1, unavailable as an
  AL2023 RPM) and shrinks the final image from 229 MB to 179 MB.

Pruned `.grype.yaml` of its 17 stale entries: 15 Alpine `apk`-type entries
left over from before the Alpine → AL2023 migration (v1.0.1), plus 2
`python`-type entries (`wheel`, `jaraco-context`) for packages vendored
inside the now-removed `python3-pip`. None of those packages exist in the
image any more. Replaced with the 10 genuinely unfixed findings (`urllib3`
×6, `setuptools` ×4 — see the sections above) so the advisory scan's own
suppression list matches what it would otherwise report.

### Remediated vulnerabilities

| CVE / Advisory | Component | Remediation |
| --- | --- | --- |
| Alpine APK CVEs (multiple) | `python3`, `busybox`, `openssh`, `unzip`, `py3-urllib3`, `py3-cryptography`, `py3-pip` | Resolved by migrating base image from Alpine 3.22 to AL2023 (v1.0.1) |
| CVE-2026-32280 — CVE-2026-33810 | supercronic Go stdlib | Partially resolved: `aws-backup-base` ships supercronic v0.2.45 (Go ≥1.26.2); newer batch of Go stdlib CVEs (33811, 33814, 39820, 39836, 42499, 42501) added to `.trivyignore` pending Go ≥1.26.3 release |
| GHSA-r6ph-v2qm-q3c2, CVE-2026-26007 | cryptography (pip) | Set `cryptography>=50.0.2` in Dockerfile |
| GHSA-gm62-xv2j-4w53 + 3 others | urllib3 (pip) | Pinned `urllib3>=2.6.3` in Dockerfile |
| GHSA-8rrh-rw8j-w5fx, CVE-2026-24049 | wheel (pip) | Pinned `wheel>=0.46.2` in Dockerfile |
| GHSA-58pv-8j8x-9vj2 | jaraco.context (pip) | Pinned `jaraco.context>=6.1.0` in Dockerfile |
| GHSA-4xh5-x5gv-qwph, CVE-2025-8869 | pip | Upgraded to pip≥25.3 (via `aws-backup-base`) |
| GHSA-jfmj-5v4g-7637, CVE-2024-5569 | zipp (pip) | Set `zipp>=3.23.1` in Dockerfile |
| CVE-2022-40897, CVE-2024-6345, CVE-2025-47273 | setuptools | Installed `setuptools>=82.0.1` via pip `--ignore-installed` to override RPM 59.6.0 |
| 8 HIGH `CVE-2026-97033`–`-97039`/`-97043`, 2 Medium `CVE-2026-97054`/`GO-2026-6859` | supercronic Go stdlib | Bumped `BASE_IMAGE` to `aws-backup-base` 1.2.3 (Go 1.27.4 builder) |
| GHSA-mrwq-x4v8-fh7p | pygments | Bumped `BASE_IMAGE` to `aws-backup-base` 1.2.3 (excludes `python3-pygments` RPM) |
| GHSA-qwm4-qh6w-59xr, GHSA-58qw-9mgm-455v | pip (RPM, build-time only) | Added `dnf remove -y python3-pip` after the Dockerfile's `pip3 install` steps |

### Test suite status

All unit tests pass. The staging integration test (`test/staging`) requires a
live Mokerlink switch and live AWS credentials; it is intentionally skipped in
automated CI and must be run manually in a network-connected environment.

## Reporting vulnerabilities

Please report security vulnerabilities through the [GitHub Security tab](https://github.com/1121citrus/mokerlink-backup/security).
Do not open a public GitHub issue for security vulnerabilities.
