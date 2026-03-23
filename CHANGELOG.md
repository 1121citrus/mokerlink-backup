# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/1121citrus/mokerlink-backup/compare/v0.0.3...HEAD
[0.0.3]: https://github.com/1121citrus/mokerlink-backup/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/1121citrus/mokerlink-backup/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/1121citrus/mokerlink-backup/releases/tag/v0.0.1
