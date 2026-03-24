# test — mokerlink-backup test suite

For detailed test documentation see **[TESTING.md](TESTING.md)**.

## Quick start

```sh
# Run the full automated suite via the build script:
./build --no-scan

# Run the automated suite directly:
IMAGE=1121citrus/mokerlink-backup:dev-abc1234 test/run-all

# Pre-release staging (requires live switch + credentials):
IMAGE=1121citrus/mokerlink-backup:1.2.3 \
  MOKERLINK_HOST=10.0.0.1 \
  MOKERLINK_PASSWORD=secret \
  test/staging
```

## Structure

| Path | Purpose |
| --- | --- |
| `run-all` | Runner — executes all automated tests |
| `mokerlink-backup` | CLI option parsing, flag validation, output format |
| `backup-required-vars` | Required-variable validation for the `backup` script |
| `backup-success` | Successful backup across all compression algorithms |
| `backup-encryption` | GPG encryption paths |
| `healthcheck` | Container health check scenarios |
| `build-options` | `build` and `staging` script option parsing |
| `staging` | Manual pre-release end-to-end tests (live switch) |
| `bin/` | Test stubs (`get-config`, `aws`) |
| `fixtures/` | Static data used by tests |
| `TESTING.md` | Full test documentation |
