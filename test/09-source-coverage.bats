#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2016  # single-quoted bash -c strings — ${VAR} expands in subshell
# test/09-source-coverage.bats — direct-execution coverage tests.
#
# Run source scripts directly (not via Docker) so kcov can instrument them.
# These tests complement the docker-based integration tests in 01–08 and are
# designed to exercise as many code paths as possible without network access
# or real hardware.
#
# Coverage targets:
#   src/common-functions                 (56 lines)
#   src/bin/backup                       (306 lines)
#   src/bin/get-backup-config            (12 lines)
#   src/bin/get-config                   (129 lines)
#   src/bin/get-running-config           (12 lines)
#   src/bin/get-startup-config           (12 lines)
#   src/bin/healthcheck                  (73 lines)
#   src/bin/mokerlink-backup             (326 lines)
#   src/bin/startup                      (114 lines)
#
# Strategy: all scripts source /usr/local/include/bash/common-functions by
# absolute path; setup() creates a symlink there pointing to the repo copy.
#
# BIN_DIR is a writable copy of src/bin/ in TEST_TMPDIR.  Scripts resolve
# bindir=$(readlink -f "$(dirname "${0}")") to BIN_DIR, so stubs placed there
# intercept sibling-script calls (get-config, pgrep/pidof/supercronic, aws,
# bzip2/gzip/xz, gpg) without requiring live infrastructure.
#
# backup tests call the real mokerlink-backup (copied to BIN_DIR) which calls
# the get-config stub; the full tar pipeline runs, with aws and compression
# stubs absorbing the upload and compression steps.

setup() {
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    TEST_TMPDIR=$(mktemp -d)
    export REPO_ROOT TEST_TMPDIR

    # Install common-functions at the absolute path all scripts hardcode.
    mkdir -p /usr/local/include/bash
    ln -sfn "${REPO_ROOT}/src/common-functions" \
        /usr/local/include/bash/common-functions

    # Version file for show_version in mokerlink-backup, backup, and startup.
    mkdir -p /usr/local/share/mokerlink-backup
    printf 'dev\n' > /usr/local/share/mokerlink-backup/version

    # Crontab directory used by healthcheck (is_crontab_configured) and startup.
    mkdir -p /var/spool/cron/crontabs

    # Writable copy of src/bin: scripts' bindir resolves to BIN_DIR, so stubs
    # placed here intercept all sibling-script calls by absolute bindir path.
    BIN_DIR="${TEST_TMPDIR}/bin"
    cp -r "${REPO_ROOT}/src/bin/." "${BIN_DIR}/"
    export BIN_DIR

    # get-config stub: emit a minimal valid switch config matching firmware
    # output format so that mokerlink-backup can extract version and hostname.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "SYSTEM CONFIG FILE ::= BEGIN\n"' \
        'printf "! System Version:  v1.0.0.27\n"' \
        'printf "! System Name: switch-test\n"' \
        > "${BIN_DIR}/get-config"
    chmod +x "${BIN_DIR}/get-config"

    # Process-detection stubs: simulate supercronic running (exit 0).
    for stub in pgrep pidof supercronic; do
        printf '#!/bin/sh\nexec /bin/true\n' > "${BIN_DIR}/${stub}"
        chmod +x "${BIN_DIR}/${stub}"
    done

    # AWS CLI stub: always exit 0 (no real S3 writes in coverage tests).
    printf '#!/bin/sh\nexec /bin/true\n' > "${BIN_DIR}/aws"
    chmod +x "${BIN_DIR}/aws"

    # Compression stubs: read stdin and write to stdout; shell handles file
    # redirects.  Avoids busybox flag incompatibilities (--keep, --synchronous).
    for stub in bzip2 gzip xz lzop pigz pixz; do
        printf '#!/bin/sh\ncat\n' > "${BIN_DIR}/${stub}"
        chmod +x "${BIN_DIR}/${stub}"
    done

    # bzip3 stub: positional input file → stdout (--batch --keep --stdout form).
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'for _a in "$@"; do case "${_a}" in -*) ;; *) _in="${_a}" ;; esac; done' \
        '[[ -n "${_in:-}" ]] && cat "${_in}"' \
        > "${BIN_DIR}/bzip3"
    chmod +x "${BIN_DIR}/bzip3"

    # zip stub: copy second positional arg to first positional arg.
    # Invocation: zip -q -9 output.zip input_file
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '_pos=()' \
        'for _a in "$@"; do case "${_a}" in -*) ;; *) _pos+=("${_a}") ;; esac; done' \
        '(( ${#_pos[@]} >= 2 )) && cp "${_pos[1]}" "${_pos[0]}"' \
        > "${BIN_DIR}/zip"
    chmod +x "${BIN_DIR}/zip"

    # expect stub: consume Tcl script from stdin; emit firmware response format.
    # Two echo-back lines followed by config content; get-config strips them via
    # tail -n +3.  Placed in BIN_DIR so passing PATH="${BIN_DIR}:${PATH}" makes
    # /usr/bin/env expect resolve to this stub.
    printf '%s\n' \
        '#!/bin/sh' \
        'cat > /dev/null' \
        'printf "show running-config\r\n"' \
        'printf "show running-config\r\n"' \
        'printf "SYSTEM CONFIG FILE ::= BEGIN\n"' \
        'printf "! System Version:  v1.0.0.27\n"' \
        'printf "! System Name: switch-test\n"' \
        > "${BIN_DIR}/expect"
    chmod +x "${BIN_DIR}/expect"

    # gpg stub: copy input file to --output destination; ignores all other
    # flags and consumes no stdin.  Handles both --passphrase-fd and
    # --passphrase-file variants.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '_out="" _in=""' \
        'while [[ $# -gt 0 ]]; do' \
        '    case "${1}" in' \
        '        --output) _out="${2}"; shift 2 ;;' \
        '        --cipher-algo|--passphrase-fd|--passphrase-file) shift 2 ;;' \
        '        --symmetric|--batch) shift ;;' \
        '        --) shift; break ;;' \
        '        -*) shift ;;' \
        '        *) _in="${1}"; shift ;;' \
        '    esac' \
        'done' \
        '[[ -n "${_out:-}" && -n "${_in:-}" && -f "${_in}" ]] && cp "${_in}" "${_out}"' \
        > "${BIN_DIR}/gpg"
    chmod +x "${BIN_DIR}/gpg"

    export INCLUDE_DIR="${REPO_ROOT}/src"
}

teardown() {
    rm -rf "${TEST_TMPDIR:-}"
}

# ── src/common-functions ──────────────────────────────────────────────────────

@test "common-functions: is_true accepts '1'" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true "1"'
    [ "$status" -eq 0 ]
}

@test "common-functions: is_true accepts 'true'" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true "true"'
    [ "$status" -eq 0 ]
}

@test "common-functions: is_true accepts 'yes'" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true "yes"'
    [ "$status" -eq 0 ]
}

@test "common-functions: is_true rejects 'false'" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true "false"'
    [ "$status" -ne 0 ]
}

@test "common-functions: is_true rejects empty string" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true ""'
    [ "$status" -ne 0 ]
}

@test "common-functions: log writes severity and message to stderr" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; log INFO "hello log"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello log"* ]]
}

@test "common-functions: log reads from stdin when no args" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"
                 echo "piped line" | log INFO'
    [ "$status" -eq 0 ]
    [[ "$output" == *"piped line"* ]]
}

@test "common-functions: debug writes DEBUG severity" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; debug "dbg msg"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG"* ]]
}

@test "common-functions: info writes INFO severity" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; info "info msg"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO"* ]]
}

@test "common-functions: ignore writes IGNORE severity" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; ignore "ign msg"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"IGNORE"* ]]
}

@test "common-functions: error exits non-zero and logs ERROR" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; error "err msg"'
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"err msg"* ]]
}

# ── src/bin/get-config ────────────────────────────────────────────────────────

@test "get-config: exits non-zero for unknown config type" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-host MOKERLINK_PASSWORD=pw \
        bash "${REPO_ROOT}/src/bin/get-config" unknowntype switch-host
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown configuration"* ]]
}

@test "get-config: exits non-zero when host is missing" {
    run env DEBUG=true \
        MOKERLINK_HOST= TAILSCALE_HOST= \
        bash "${REPO_ROOT}/src/bin/get-config" running
    [ "$status" -ne 0 ]
    [[ "$output" == *"need hostname"* ]]
}

@test "get-config: exits non-zero when password is missing" {
    run env DEBUG=true \
        MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/nonexistent-pw" \
        bash "${REPO_ROOT}/src/bin/get-config" running switch-host
    [ "$status" -ne 0 ]
    [[ "$output" == *"need password"* ]]
}

@test "get-config: success path with mocked expect emits config lines" {
    # BIN_DIR/expect stub is in PATH; get-config prepends its own bindir, then
    # falls through to BIN_DIR when searching for /usr/bin/env expect.
    run env DEBUG=true \
        PATH="${BIN_DIR}:${PATH}" \
        MOKERLINK_PASSWORD=pw \
        bash "${REPO_ROOT}/src/bin/get-config" running switch-host
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYSTEM CONFIG FILE"* ]]
}

@test "get-config: startup config via mocked expect" {
    run env \
        PATH="${BIN_DIR}:${PATH}" \
        MOKERLINK_PASSWORD=pw \
        bash "${REPO_ROOT}/src/bin/get-config" startup switch-host
    [ "$status" -eq 0 ]
}

@test "get-config: backup config via mocked expect" {
    run env \
        PATH="${BIN_DIR}:${PATH}" \
        MOKERLINK_PASSWORD=pw \
        bash "${REPO_ROOT}/src/bin/get-config" backup switch-host
    [ "$status" -eq 0 ]
}

# ── src/bin/get-*-config wrappers ─────────────────────────────────────────────
# These wrappers call "${bindir}/get-config" which resolves to the stub.

@test "get-running-config: delegates to get-config stub" {
    run bash "${BIN_DIR}/get-running-config" switch-host
    [ "$status" -eq 0 ]
}

@test "get-startup-config: delegates to get-config stub" {
    run bash "${BIN_DIR}/get-startup-config" switch-host
    [ "$status" -eq 0 ]
}

@test "get-backup-config: delegates to get-config stub" {
    run bash "${BIN_DIR}/get-backup-config" switch-host
    [ "$status" -eq 0 ]
}

# ── src/bin/mokerlink-backup ──────────────────────────────────────────────────

@test "mokerlink-backup: --help exits 0" {
    run bash "${BIN_DIR}/mokerlink-backup" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Download a backup"* ]]
}

@test "mokerlink-backup: --version exits 0" {
    run bash "${BIN_DIR}/mokerlink-backup" --version
    [ "$status" -eq 0 ]
}

@test "mokerlink-backup: unknown option exits non-zero" {
    run bash "${BIN_DIR}/mokerlink-backup" --notarealflag
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "mokerlink-backup: unexpected positional argument exits non-zero" {
    run env MOKERLINK_HOST=switch-test MOKERLINK_PASSWORD=pw \
        bash "${BIN_DIR}/mokerlink-backup" unexpected_arg
    [ "$status" -ne 0 ]
    [[ "$output" == *"unexpected argument"* ]]
}

@test "mokerlink-backup: exits non-zero when MOKERLINK_HOST unset" {
    run env MOKERLINK_HOST= TAILSCALE_HOST= MOKERLINK_PASSWORD=pw \
        bash "${BIN_DIR}/mokerlink-backup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"MOKERLINK_HOST"* ]]
}

@test "mokerlink-backup: exits non-zero when password missing" {
    run env \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/nonexistent-pw" \
        bash "${BIN_DIR}/mokerlink-backup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"MOKERLINK_PASSWORD"* ]]
}

@test "mokerlink-backup: exits non-zero for unknown format" {
    run env MOKERLINK_HOST=switch-test MOKERLINK_PASSWORD=pw \
        bash "${BIN_DIR}/mokerlink-backup" --format badformat
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown format"* ]]
}

@test "mokerlink-backup: exits non-zero when all configs excluded" {
    run env MOKERLINK_HOST=switch-test MOKERLINK_PASSWORD=pw \
        bash "${BIN_DIR}/mokerlink-backup" \
        --no-running --no-startup --no-backup
    [ "$status" -ne 0 ]
    [[ "$output" == *"no configurations selected"* ]]
}

@test "mokerlink-backup: tar format with all configs succeeds" {
    NAME_FILE="${TEST_TMPDIR}/backup-name"
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        MOKERLINK_BACKUP_NAME_FILE="${NAME_FILE}" \
        bash "${BIN_DIR}/mokerlink-backup" --all
    [ "$status" -eq 0 ]
}

@test "mokerlink-backup: raw format with --running succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        bash "${BIN_DIR}/mokerlink-backup" --running --format raw
    [ "$status" -eq 0 ]
}

@test "mokerlink-backup: --no-running excludes running config" {
    NAME_FILE="${TEST_TMPDIR}/backup-name-2"
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        MOKERLINK_BACKUP_NAME_FILE="${NAME_FILE}" \
        bash "${BIN_DIR}/mokerlink-backup" --startup --no-running
    [ "$status" -eq 0 ]
}

@test "mokerlink-backup: password read from --password-file" {
    PW_FILE="${TEST_TMPDIR}/pw-file"
    printf 'filepassword\n' > "${PW_FILE}"
    NAME_FILE="${TEST_TMPDIR}/backup-name-3"
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD= \
        MOKERLINK_BACKUP_NAME_FILE="${NAME_FILE}" \
        bash "${BIN_DIR}/mokerlink-backup" \
        --running --password-file "${PW_FILE}"
    [ "$status" -eq 0 ]
}

@test "mokerlink-backup: --user and --password options accepted" {
    NAME_FILE="${TEST_TMPDIR}/backup-name-4"
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_BACKUP_NAME_FILE="${NAME_FILE}" \
        bash "${BIN_DIR}/mokerlink-backup" \
        --running --user testuser --password testpw
    [ "$status" -eq 0 ]
}

# ── src/bin/healthcheck ───────────────────────────────────────────────────────

@test "healthcheck: exits 0 when crontab ok, supercronic mocked, no sentinel" {
    crontab_file="/var/spool/cron/crontabs/$(id -un)"
    printf '%s\n' '* * * * * /usr/local/bin/backup' > "${crontab_file}"
    run env DEBUG=true PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/healthcheck"
    [ "$status" -eq 0 ]
}

@test "healthcheck: exits 0 when sentinel file is fresh" {
    crontab_file="/var/spool/cron/crontabs/$(id -un)"
    printf '%s\n' '* * * * * /usr/local/bin/backup' > "${crontab_file}"
    sentinel="${TEST_TMPDIR}/last-success"
    touch "${sentinel}"
    run env DEBUG=true PATH="${BIN_DIR}:${PATH}" \
        BACKUP_SENTINEL_FILE="${sentinel}" \
        bash "${BIN_DIR}/healthcheck"
    [ "$status" -eq 0 ]
}

@test "healthcheck: exits non-zero when sentinel is stale" {
    crontab_file="/var/spool/cron/crontabs/$(id -un)"
    printf '%s\n' '* * * * * /usr/local/bin/backup' > "${crontab_file}"
    sentinel="${TEST_TMPDIR}/last-success-stale"
    touch -t 200001010000.00 "${sentinel}"
    run env DEBUG=true PATH="${BIN_DIR}:${PATH}" \
        BACKUP_SENTINEL_FILE="${sentinel}" \
        BACKUP_MAX_AGE_SECONDS=1 \
        bash "${BIN_DIR}/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"s old"* ]]
}

@test "healthcheck: exits non-zero when crontab not configured" {
    rm -f "/var/spool/cron/crontabs/$(id -un)"
    run env DEBUG=true PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"crontab is not configured"* ]]
}

@test "healthcheck: exits non-zero when supercronic not running" {
    crontab_file="/var/spool/cron/crontabs/$(id -un)"
    printf '%s\n' '* * * * * /usr/local/bin/backup' > "${crontab_file}"
    # Replace success stubs with fail stubs to simulate supercronic absent.
    printf '#!/bin/sh\nexec /bin/false\n' > "${BIN_DIR}/pgrep"
    printf '#!/bin/sh\nexec /bin/false\n' > "${BIN_DIR}/pidof"
    run env DEBUG=true PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"supercronic is not running"* ]]
}

# ── src/bin/startup ───────────────────────────────────────────────────────────

@test "startup: --help exits 0" {
    run bash "${BIN_DIR}/startup" --help
    [ "$status" -eq 0 ]
}

@test "startup: --version exits 0" {
    run bash "${BIN_DIR}/startup" --version
    [ "$status" -eq 0 ]
}

@test "startup: unknown option exits non-zero" {
    run bash "${BIN_DIR}/startup" --notarealflag
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "startup: installs crontab and execs supercronic" {
    run env DEBUG=true \
        AWS_S3_BUCKET_NAME=test-bucket \
        ENV="${TEST_TMPDIR}/.startup-env" \
        HOME="${TEST_TMPDIR}" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/startup"
    [ "$status" -eq 0 ]
}

# ── src/bin/backup ────────────────────────────────────────────────────────────

@test "backup: --help exits 0" {
    run bash "${BIN_DIR}/backup" --help
    [ "$status" -eq 0 ]
}

@test "backup: --version exits 0" {
    run bash "${BIN_DIR}/backup" --version
    [ "$status" -eq 0 ]
}

@test "backup: exits non-zero for unknown option" {
    run bash "${BIN_DIR}/backup" --notarealflag
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "backup: exits non-zero when AWS_S3_BUCKET_NAME unset" {
    run env -u AWS_S3_BUCKET_NAME \
        MOKERLINK_HOST=switch-test MOKERLINK_PASSWORD=pw \
        bash "${BIN_DIR}/backup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"AWS_S3_BUCKET_NAME"* ]]
}

@test "backup: full backup with COMPRESSION=none succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=none \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: --dryrun flag is accepted" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=none \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup" --dryrun
    [ "$status" -eq 0 ]
}

@test "backup: bzip2 compression succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=bzip2 \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: gz compression succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=gz \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: xz compression succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=xz \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: lzop compression succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=lzo \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: pigz compression succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=pigz \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: pixz compression succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=pixz \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: bzip3 compression succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=bzip3 \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: zip compression succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=zip \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: GPG passphrase encryption succeeds" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=none \
        GPG_PASSPHRASE=testpassphrase \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: GPG passphrase-file encryption succeeds" {
    PW_FILE="${TEST_TMPDIR}/gpg-pw"
    printf 'secretkey\n' > "${PW_FILE}"
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=none \
        GPG_PASSPHRASE= \
        GPG_PASSPHRASE_FILE="${PW_FILE}" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -eq 0 ]
}

@test "backup: unknown compression exits non-zero" {
    run env DEBUG=true \
        MOKERLINK_HOST=switch-test \
        MOKERLINK_PASSWORD=pw \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=badcompressor \
        GPG_PASSPHRASE_FILE="${TEST_TMPDIR}/nonexistent-gpg" \
        PATH="${BIN_DIR}:${PATH}" \
        bash "${BIN_DIR}/backup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown compression"* ]]
}
