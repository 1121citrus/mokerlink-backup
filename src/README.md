# src — mokerlink-backup source

Scripts and libraries installed into the container image.

For full script reference documentation — including design notes for `get-config`'s
`expect` session, the filename-sidecar mechanism, and the config selection model —
see **[src/bin/README.md](bin/README.md)**.

## Structure

| Path | Purpose |
| --- | --- |
| `bin/` | Executable scripts installed to `/usr/local/bin` |
| `common-functions` | Shared utility library installed to `/usr/local/include/1121citrus/` |

## Script summary

| Script | Role |
| --- | --- |
| `bin/mokerlink-backup` | **Primary CLI** — downloads switch configs, streams tar or raw text to stdout |
| `bin/get-config` | SSH engine — `expect`-driven SSH session against the Mokerlink firmware |
| `bin/get-running-config` | Backward-compat wrapper: `get-config running "$@"` |
| `bin/get-startup-config` | Backward-compat wrapper: `get-config startup "$@"` |
| `bin/get-backup-config` | Backward-compat wrapper: `get-config backup "$@"` |
| `bin/backup` | Legacy service script — fetch, compress, encrypt, upload to S3 |
| `bin/startup` | Container entrypoint — writes `.env`, installs crontab, execs `crond` |
| `bin/healthcheck` | Docker `HEALTHCHECK` — verifies `crond` and crontab are active |

## `common-functions`

Shared utility library sourced by `backup`, `startup`, and `healthcheck`.
Provides structured logging, `is_true`/`is_false` boolean helpers, and
`not_blank` variable guards.
