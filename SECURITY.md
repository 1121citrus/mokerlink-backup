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

- The container runs as `root` because Alpine's `crond` requires it.  If the
  switch user can be run as non-root in a future revision, consider adding a
  dedicated UID.
- The `~/.gnupg` and `~/.ssh` directories are created with mode `700` and
  `~/.gnupg/pubring.kbx` with mode `600` in the Dockerfile.
- No ports are exposed; the container initiates all outbound connections.
- The image is built with `--sbom=true --provenance=mode=max` to enable supply
  chain attestation inspection.

## Dependency provenance

The Docker image is built on `alpine:3.21` (official Docker Hub image).  All
packages are installed from the Alpine package index pinned to version
constraints in the `Dockerfile`.  The CI pipeline runs a
[Trivy](https://github.com/aquasecurity/trivy) vulnerability scan after every
build and fails on unfixed CVEs.

Supply chain attestations (SBOM + provenance) are attached to every published
image and can be inspected with:

```console
docker buildx imagetools inspect 1121citrus/mokerlink-backup:<version> \
    --format '{{json .SBOM}}'
docker buildx imagetools inspect 1121citrus/mokerlink-backup:<version> \
    --format '{{json .Provenance}}'
```

## Reporting vulnerabilities

Report security issues to [jim@hanlonsoftware.com](mailto:jim@hanlonsoftware.com).
