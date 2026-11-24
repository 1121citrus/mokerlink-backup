# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.4] - 2026-11-24

### Security

- Run every `dnf install`/`upgrade`/`reinstall` in the `Dockerfile` with
  `--releasever=latest`. AL2023 locks dnf to the base image's release, so
  `dnf upgrade` could not reach newer fixes.
- Pin `aws-backup-base` by digest, bumped from 1.2.2 to 1.2.3
  (`sha256:dc4c176e47b9d1b818c149466bcb61ed2e5ea643a0d947d6b8fc8519b2b14852`)
  instead of `:latest`, so builds are reproducible. 1.2.3 builds
  `supercronic` with Go 1.27.4 instead of 1.27.3 and excludes the
  `python3-pygments` RPM, clearing 10 Go `stdlib` CVEs and
  `GHSA-mrwq-x4v8-fh7p` (pygments).
- Together the digest pin and `--releasever=latest` clear 55 gating
  Trivy HIGH findings in AL2023 packages (including `curl-minimal`)
  without suppression.
- Prune every now-unneeded AL2023 OS-package, `python3-pip` RPM, and
  `supercronic` Go stdlib entry from `.trivyignore`.
- Suppress `CVE-2026-97687`/`CVE-2026-97689` (`urllib3` 2.6.3, HIGH):
  the fix (`urllib3` 2.8.0) requires Python >= 3.10 and the base image
  ships Python 3.9.
- Remove `python3-pip` from the image after the `Dockerfile`'s `pip3
  install` steps run; it is build-time tooling only — nothing in `src/`
  or `test/` calls `pip`/`pip3` at runtime. Clears the `pip` 21.3.1
  Medium findings `GHSA-qwm4-qh6w-59xr` and `GHSA-58qw-9mgm-455v` and
  shrinks the image from 229 MB to 179 MB.
- Add `.scout.vex.json`, an OpenVEX document suppressing the two
  `perl-*` CVEs (`CVE-2023-31484`, `CVE-2023-31486`) Docker Scout
  reports as false positives — it compares each subpackage's own
  release against the wrong `perl` source-package fix version.
- Add `.scoutignore`, listing the 12 Docker Scout findings (`urllib3`
  on both the RPM 1.25.10 and pip 2.6.3 copies, `setuptools` on the RPM
  59.6.0 copy) reviewed and accepted as currently unfixable, blocked by
  the base image's Python 3.9. `build` Stage 4c now checks Scout's
  findings against this list instead of trusting its own `--exit-code`,
  so a reviewed finding no longer fails the build.
- Prune 17 stale Alpine-era entries from `.grype.yaml` left over from
  before the Alpine -> AL2023 migration (v1.0.1); replace with the
  10 findings genuinely still unfixed on the current base (`urllib3`
  x6, `setuptools` x4).
- Document two new Grype-only findings against `setuptools`
  (`GHSA-h35f-9h28-mq5c` Medium, `GHSA-xmj3-9gf7-h52w` Low), blocked by
  the same Python 3.9 constraint.
- Add static `Dockerfile` regression tests for `--releasever=latest` and the
  digest-pinned base image.

### Changed

- `build`: a failing Trivy or Docker Scout gating scan no longer aborts
  the script immediately. The failure is now recorded and the script
  continues through Grype and every advisory stage that was requested;
  Stage 6 Push still refuses to run, and the script still exits with
  the original failing status at the end.

## [1.0.3] - 2026-05-05

### Added

- Gitleaks CI workflow (`.github/workflows/gitleaks-ci.yml`) scans the
  repository for leaked secrets on every push and pull request
- `gitleaks` advisement in `build` script (`--advise gitleaks`, Stage 5e);
  non-gating, advisory only

### Changed

- Bump tool image versions in `build` and `test/staging`: `grype` v0.87.0 →
  v0.112.0, `trivy` 0.62.1 → 0.70.0, `hadolint` v2.12.0 → v2.14.0,
  `shellcheck` v0.10.0 → v0.11.0
- Filter small inefficient-file entries from Dive advisory output in
  `test/staging`; entries below `DIVE_MIN_WASTED_BYTES` (default 1 MB) are
  suppressed to reduce noise

## [1.0.2] - 2026-05-02

### Security

- Suppress five unfixable AL2023 CVEs in `.trivyignore`: `CVE-2026-4046`
  (glibc iconv DoS), `CVE-2026-3644`, `CVE-2026-4786`, `CVE-2026-6100`
  (cpython), `CVE-2026-35385` (openssh scp); fix versions are identified
  by Trivy but not yet available in the AL2023 package repositories

### Changed

- Regenerate `build`, `test/run-all`, `test/staging` from generator
  commit `27d0e5c`; staging Trivy scan now mounts `.trivyignore` from
  the repo root, matching the build script's own scan stage

## [1.0.1] - 2026-04-27

### Changed

- Migrate base image from Alpine to Amazon Linux 2023 (AL2023); replace
  `apk` with `dnf`; switch runtime packages to AL2023 equivalents
- Bump `actions/checkout` v4 → v6.0.2
- Bump `actions/download-artifact` v4 → v8.0.1
- Switch Dependabot schedule from weekly to daily; remove stale Docker
  ecosystem block (no direct `FROM` line in Dockerfile)

## [1.0.0] - 2026-04-26

### Changed
- Developer features added to build and staging test scripts

## [0.0.3] - 2026-03-22

### Added
- Docker Scout CVE advisement to build tool (`--advise scout`)
- Dive image layer analysis to build tool (`--advise dive`; opt-in)

## [0.0.2] - 2026-03-22

### Fixed
- Code, documentation, and test coverage review findings

## [0.0.1] - 2026-03-19

### Added
- Initial release of mokerlink-backup
- Support for backing up Mikrotik RouterOS configurations to S3
- Scheduled backups via cron
- Optional GPG encryption of backup archives
- Optional compression (gzip, bzip3, xz, zstd)
- Dry-run mode enabled by default for safety
- DRYRUN=false required for live backup operations
- Health-check endpoint to verify cron job execution
- SLSA Level 3 provenance attestations
- SBOM (Software Bill of Materials) generation

### Security
- Non-root execution (UID 10001)
- Minimal Alpine base image
- Docker secret support for credentials
- Expect buffer increased to 1MB for large configurations
- GPG encryption via passphrase or file

---

[Unreleased]: https://github.com/1121citrus/mokerlink-backup/compare/v1.0.4...HEAD
[1.0.4]: https://github.com/1121citrus/mokerlink-backup/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/1121citrus/mokerlink-backup/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/1121citrus/mokerlink-backup/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/1121citrus/mokerlink-backup/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/1121citrus/mokerlink-backup/compare/v0.0.3...v1.0.0
[0.0.3]: https://github.com/1121citrus/mokerlink-backup/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/1121citrus/mokerlink-backup/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/1121citrus/mokerlink-backup/releases/tag/v0.0.1
