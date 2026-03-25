# GitHub CI Workflows

Automated linting, building, testing, security scanning, and Docker image publication for mokerlink-backup.

## Workflow Overview

| Stage          | Trigger                                    | Purpose                                          |
| -------------- | ------------------------------------------ | ------------------------------------------------ |
| **Lint**       | All pushes to main/staging, PRs, tags      | Validate Dockerfile and shell scripts            |
| **Build**      | After lint                                 | Build image and share as artifact                |
| **Test**       | After build (parallel with scan)           | Run full test suite against built image          |
| **Scan**       | After build (parallel with test)           | Trivy image scan — blocks push on fixable CVEs   |
| **Push**       | Version tags and staging branch only       | Multi-platform build and push to Docker Hub      |
| **Dependabot** | Weekly (Monday 06:00 UTC)                  | Keep GitHub Actions versions current             |

## CI Workflow (`ci.yml`)

Single unified workflow for all CI/CD stages.

### Trigger Events

- **Push:** `main`, `staging` branches and `v*` version tags
- **Pull requests:** To `main` branch

### Concurrency

- **Group:** `<workflow-name>-<ref>` — one concurrent run per workflow + branch/tag
- **Branches and PRs:** Cancel any in-progress run when a newer one starts
- **Version tags:** Never cancelled — release builds always complete

### Versioning

Tag-driven. Push a git tag to publish a release:

```bash
git tag v1.2.3
git push origin v1.2.3
# Publishes: 1121citrus/mokerlink-backup:1.2.3 + :latest
```

No automation bumps the version — the tag is always a deliberate decision.

---

## Stage 1: Lint

- **Hadolint** — Dockerfile best-practice checks
- **ShellCheck** — static analysis of all executable shell scripts:
  - `build`
  - `src/common-functions`, `src/bin/backup`, `src/bin/get-backup-config`, `src/bin/get-config`, `src/bin/get-running-config`, `src/bin/get-startup-config`, `src/bin/healthcheck`, `src/bin/mokerlink-backup`, `src/bin/startup`
  - `test/run-all`, `test/backup-required-vars`, `test/backup-success`, `test/backup-encryption`, `test/build-options`, `test/healthcheck`, `test/mokerlink-backup`, `test/staging`, `test/bin/*`

---

## Stage 2: Build

Builds image for the host platform (`linux/amd64`) and exports it as a GitHub Actions artifact (`docker-image`). The image is re-tagged as `:latest` so test scripts that default to `IMAGE:latest` work without modification.

Artifact retention: 1 day (sufficient for the duration of the workflow).

---

## Stage 3: Test

Runs in parallel with the scan job. Downloads the artifact, loads the image, and executes the full test suite via `test/run-all`:

- `mokerlink-backup` — validates CLI option parsing, config selection flags, and output formats
- `backup-required-vars` — validates required environment variables
- `backup-success` — verifies successful backup operation
- `backup-encryption` — tests backup encryption
- `healthcheck` — exercises the container health check

---

## Stage 4: Security scan

Runs in parallel with the test job. Scans the local image **before** it is pushed to Docker Hub.

- **Tool:** Trivy `aquasecurity/trivy-action@0.35.0` (pinned)
- **Severity:** CRITICAL, HIGH
- **Blocking:** `exit-code: 1` — fails and blocks push if fixable CVEs found
- **Noise reduction:** `ignore-unfixed: true` — suppresses CVEs with no available patch
- **DB caching:** `~/.cache/trivy` is cached between runs with `actions/cache`; the
  vulnerability DB is only re-downloaded when the cache is cold or the DB has been updated
- **Download noise:** `TRIVY_NO_PROGRESS=true` suppresses progress bars; `TRIVY_QUIET=true`
  suppresses `INFO [vulndb]` log lines during DB download

---

## Stage 5: Push to Docker Hub

Runs only when test and scan both pass, and only on version tags or the staging branch.

### Tagging

| Trigger           | Docker Hub tags                                                |
| ----------------- | -------------------------------------------------------------- |
| Tag `v1.2.3`      | `1121citrus/mokerlink-backup:1.2.3` + `:latest`                |
| Push to `staging` | `1121citrus/mokerlink-backup:staging-<timestamp>` + `:staging` |

- `:latest` is set **only** on version-tagged releases
- Staging gets a datetime timestamp (`staging-2026.03.18.134500`) for traceability

### Build configuration

- **Platforms:** `linux/amd64`, `linux/arm64`
- **Attestations:** `sbom: true` + `provenance: mode=max` (SLSA L3)

---

## Execution Flow

```text
On push to main/staging or PR to main
    ↓
[Lint] — hadolint + shellcheck
    ↓
[Build] — single-arch image → artifact
    ↓ (parallel)
[Test]                        [Scan]
 - load artifact               - load artifact
 - run test/run-all            - Trivy CRITICAL/HIGH
 - ✅/❌                        - ✅/❌ blocks push

[Push] (tags and staging only, after Test + Scan pass)
 - QEMU + Buildx multi-arch
 - push amd64 + arm64
 - SBOM + provenance
```

---

## Configuration Reference

### Required Secrets

- `DOCKERHUB_USERNAME` — Docker Hub account
- `DOCKERHUB_TOKEN` — Docker Hub access token

### Key Files

- `Dockerfile` — Container build definition
- `src/` — Application shell scripts
- `test/run-all` — Test runner
- `test/mokerlink-backup`, `test/backup-*`, `test/healthcheck` — Individual test scripts
- `test/bin/` — Mock binaries used by tests

## Automated dependency updates

`dependabot.yml` configures weekly automated PRs to keep GitHub Actions current.

- **Schedule:** Every Monday at 06:00 UTC
- **Scope:** GitHub Actions (`package-ecosystem: github-actions`) — updates action pins in
  `.github/workflows/*.yml`
- **Labels:** `dependencies`, `github-actions`
- **Security benefit:** Dependabot also proposes SHA-pinned digests (recommended for SLSA /
  OpenSSF Scorecard hardening)

---

## Local Workflow Parity

- `./build` supports `--advice` (alias for `--advise`) and `--cache` for one-run scanner cache controls.
- `test/staging` supports `--scan`, `--no-scan`, `--advise`, and `--no-advise` for live-image validation.
