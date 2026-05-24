#!/usr/bin/env bats
# shellcheck shell=bash
# test/12-mokerlink-backup-serial.bats — unit tests for serial transport in
# src/bin/mokerlink-backup.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Tests run directly against the source scripts (no Docker) following the
# pattern established in test/10-mokerlink-restore.bats.  The get-config-serial
# transport engine is replaced by a stub so no hardware or serial port is needed.

setup() {
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    TEST_TMPDIR=$(mktemp -d)
    export REPO_ROOT TEST_TMPDIR

    mkdir -p /usr/local/include/bash
    ln -sfn "${REPO_ROOT}/src/common-functions" \
        /usr/local/include/bash/common-functions

    mkdir -p /usr/local/share/mokerlink-backup
    printf 'dev\n' > /usr/local/share/mokerlink-backup/version

    # Writable copy of src/bin; stubs placed here intercept sibling calls.
    BIN_DIR="${TEST_TMPDIR}/bin"
    cp -r "${REPO_ROOT}/src/bin/." "${BIN_DIR}/"
    export BIN_DIR

    # A fake serial device character file.  mknod requires root; use /dev/null
    # via a symlink so -c tests can be stubbed out via FAKE_PORT overrides in
    # mokerlink-backup's auto-detect loop.  Direct --port usage just passes the
    # path through to the stub, so any path works.
    FAKE_PORT="${TEST_TMPDIR}/fake-serial"
    # Create a FIFO so the path exists; the stub never actually reads it.
    mkfifo "${FAKE_PORT}"
    export FAKE_PORT

    # Minimal config output the stub emits — enough for mokerlink-backup to
    # extract version and hostname from.
    STUB_CONFIG="SYSTEM CONFIG FILE ::= BEGIN
! System Description: KT-NOS POE-G244GSM Switch
! System Version: v1.2.3
! System Name: test-switch
system name \"test-switch\"
"
    export STUB_CONFIG

    # get-config-serial stub: emits minimal valid config and exits 0.
    # Records invocation args to stderr for assertion.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "stub get-config-serial: %s\n" "$*" >&2' \
        'printf "%s\n" "${STUB_CONFIG}"' \
        'exit 0' \
        > "${BIN_DIR}/get-config-serial"
    chmod +x "${BIN_DIR}/get-config-serial"

    # get-config stub: should NOT be called for serial transport.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "ERROR: get-config called unexpectedly for serial transport\n" >&2' \
        'exit 1' \
        > "${BIN_DIR}/get-config"
    chmod +x "${BIN_DIR}/get-config"
}

teardown() {
    rm -rf "${TEST_TMPDIR:-}"
}

# ── Transport validation ──────────────────────────────────────────────────────

@test "mokerlink-backup: --transport serial accepted" {
    run bash "${BIN_DIR}/mokerlink-backup" \
        --transport serial \
        --port "${FAKE_PORT}" \
        --running \
        --format raw
    [ "$status" -eq 0 ]
}

@test "mokerlink-backup: --transport ssh still works (backward compat)" {
    # Replace get-config stub with one that succeeds so SSH path can run.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\n" "${STUB_CONFIG}"' \
        'exit 0' \
        > "${BIN_DIR}/get-config"
    chmod +x "${BIN_DIR}/get-config"

    run env MOKERLINK_HOST=192.168.2.1 MOKERLINK_PASSWORD=test \
        bash "${BIN_DIR}/mokerlink-backup" \
        --transport ssh \
        --host 192.168.2.1 \
        --running \
        --format raw
    [ "$status" -eq 0 ]
}

@test "mokerlink-backup: unknown --transport exits non-zero" {
    run bash "${BIN_DIR}/mokerlink-backup" \
        --transport badtransport \
        --running \
        --format raw
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown transport"* ]]
}

# ── Serial transport: port handling ──────────────────────────────────────────

@test "mokerlink-backup: --port accepted with serial transport" {
    run bash "${BIN_DIR}/mokerlink-backup" \
        --transport serial \
        --port "${FAKE_PORT}" \
        --running \
        --format raw
    [ "$status" -eq 0 ]
}

@test "mokerlink-backup: serial transport exits non-zero when no port found" {
    # Only fails when no real serial ports exist on the host.
    for _c in /dev/cu.usbserial-* /dev/ttyUSB0 /dev/ttyACM0; do
        [[ -c "${_c}" ]] && skip "real serial port present; skipping"
    done
    run bash "${BIN_DIR}/mokerlink-backup" \
        --transport serial \
        --running \
        --format raw
    [ "$status" -ne 0 ]
    [[ "$output" == *"no serial port found"* ]]
}

# ── Serial transport: password handling ──────────────────────────────────────

@test "mokerlink-backup: serial transport defaults to admin when no password given" {
    run env MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/nonexistent-pw" \
        bash "${BIN_DIR}/mokerlink-backup" \
        --transport serial \
        --port "${FAKE_PORT}" \
        --running \
        --format raw
    # Should succeed — factory default 'admin' is used silently.
    [ "$status" -eq 0 ]
}

@test "mokerlink-backup: serial transport uses MOKERLINK_PASSWORD when set" {
    run env MOKERLINK_PASSWORD=mypassword \
        bash "${BIN_DIR}/mokerlink-backup" \
        --transport serial \
        --port "${FAKE_PORT}" \
        --running \
        --format raw
    [ "$status" -eq 0 ]
}

@test "mokerlink-backup: serial transport reads password from file" {
    printf '%s' 'filepassword' > "${TEST_TMPDIR}/pw"
    run env MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/pw" \
        bash "${BIN_DIR}/mokerlink-backup" \
        --transport serial \
        --port "${FAKE_PORT}" \
        --running \
        --format raw
    [ "$status" -eq 0 ]
}

# ── SSH transport: still requires host and password ──────────────────────────

@test "mokerlink-backup: ssh transport requires --host" {
    # Replace get-config stub with a successful one so the only failure path
    # is the missing-host validation.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\n" "${STUB_CONFIG}"' \
        'exit 0' \
        > "${BIN_DIR}/get-config"
    chmod +x "${BIN_DIR}/get-config"

    run env MOKERLINK_HOST= TAILSCALE_HOST= MOKERLINK_PASSWORD=test \
        bash "${BIN_DIR}/mokerlink-backup" \
        --transport ssh \
        --running \
        --format raw
    [ "$status" -ne 0 ]
    [[ "$output" == *"MOKERLINK_HOST"* || "$output" == *"--host"* ]]
}

@test "mokerlink-backup: ssh transport requires password" {
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\n" "${STUB_CONFIG}"' \
        'exit 0' \
        > "${BIN_DIR}/get-config"
    chmod +x "${BIN_DIR}/get-config"

    run env MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/nonexistent-pw" \
        bash "${BIN_DIR}/mokerlink-backup" \
        --transport ssh \
        --host 192.168.2.1 \
        --running \
        --format raw
    [ "$status" -ne 0 ]
    [[ "$output" == *"MOKERLINK_PASSWORD"* ]]
}

# ── Output format ─────────────────────────────────────────────────────────────

@test "mokerlink-backup: serial transport raw format emits config text" {
    run bash "${BIN_DIR}/mokerlink-backup" \
        --transport serial \
        --port "${FAKE_PORT}" \
        --running \
        --format raw
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYSTEM CONFIG FILE"* ]]
}

@test "mokerlink-backup: serial transport tar format produces a tar archive" {
    local out_file="${TEST_TMPDIR}/backup.tar"
    bash "${BIN_DIR}/mokerlink-backup" \
        --transport serial \
        --port "${FAKE_PORT}" \
        --running \
        --format tar > "${out_file}"
    tar -tf "${out_file}" > /dev/null
}
