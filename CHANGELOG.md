# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/1121citrus/mokerlink-backup/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/1121citrus/mokerlink-backup/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/1121citrus/mokerlink-backup/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/1121citrus/mokerlink-backup/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/1121citrus/mokerlink-backup/compare/v0.0.3...v1.0.0
[0.0.3]: https://github.com/1121citrus/mokerlink-backup/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/1121citrus/mokerlink-backup/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/1121citrus/mokerlink-backup/releases/tag/v0.0.1
