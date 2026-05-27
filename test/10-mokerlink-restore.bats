#!/usr/bin/env bats
# shellcheck shell=bash
# test/10-mokerlink-restore.bats — unit tests for src/bin/mokerlink-restore.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Tests run directly against the source scripts (no Docker) following the
# pattern established in test/09-source-coverage.bats.  Transport engines
# are replaced by stubs in BIN_DIR so no hardware or network is needed.

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

    # A minimal config file to satisfy --config validation.
    CFG="${TEST_TMPDIR}/test.cfg"
    printf 'SYSTEM CONFIG FILE ::= BEGIN\n' > "${CFG}"
    export CFG

    # set-config-serial stub: records its arguments and exits 0.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "stub set-config-serial: %s\n" "$*" >&2' \
        'exit 0' \
        > "${BIN_DIR}/set-config-serial"
    chmod +x "${BIN_DIR}/set-config-serial"

    # set-config-http stub.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "stub set-config-http: %s\n" "$*" >&2' \
        'exit 0' \
        > "${BIN_DIR}/set-config-http"
    chmod +x "${BIN_DIR}/set-config-http"

    # set-config-ssh stub.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "stub set-config-ssh: %s\n" "$*" >&2' \
        'exit 0' \
        > "${BIN_DIR}/set-config-ssh"
    chmod +x "${BIN_DIR}/set-config-ssh"

    # set-config-cmd stub.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "stub set-config-cmd: %s\n" "$*" >&2' \
        'exit 0' \
        > "${BIN_DIR}/set-config-cmd"
    chmod +x "${BIN_DIR}/set-config-cmd"

    # set-config-cmd-serial stub.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "stub set-config-cmd-serial: %s\n" "$*" >&2' \
        'exit 0' \
        > "${BIN_DIR}/set-config-cmd-serial"
    chmod +x "${BIN_DIR}/set-config-cmd-serial"

    # tftp-serve stub: sleeps until killed (mimics a real server for the
    # kill -0 liveness check in start_tftp(); cleanup() sends SIGTERM).
    # sleep runs in background so the trap fires immediately when bash
    # receives SIGTERM (a foreground sleep defers the trap until it exits).
    # Single-quoted heredoc delimiter prevents bash expanding ${_pid} here;
    # it expands correctly when the stub script runs.
    cat > "${BIN_DIR}/tftp-serve" <<'__STUB__'
#!/usr/bin/env bash
_pid=
trap 'kill "${_pid}" 2>/dev/null; exit 0' TERM INT
sleep 300 &
_pid=$!
wait
__STUB__
    chmod +x "${BIN_DIR}/tftp-serve"

    # wait-for-restart stub: exits 0 immediately.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'exit 0' \
        > "${BIN_DIR}/wait-for-restart"
    chmod +x "${BIN_DIR}/wait-for-restart"

    # Provide a fake serial device character file for auto-detect tests.
    # mknod requires root; instead we create a named pipe that satisfies
    # -c by substituting a symlink to /dev/null where needed via the
    # SERIAL_PORT override.
    FAKE_PORT="${TEST_TMPDIR}/fake-serial"
    export FAKE_PORT
}

teardown() {
    rm -rf "${TEST_TMPDIR:-}"
}

# ── --help / --version ────────────────────────────────────────────────────────

@test "mokerlink-restore: --help exits 0 and prints usage" {
    run bash "${BIN_DIR}/mokerlink-restore" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--transport"* ]]
}

@test "mokerlink-restore: -h exits 0 and prints usage" {
    run bash "${BIN_DIR}/mokerlink-restore" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--transport"* ]]
}

@test "mokerlink-restore: --version exits 0" {
    run bash "${BIN_DIR}/mokerlink-restore" --version
    [ "$status" -eq 0 ]
}

# ── Required-argument validation ──────────────────────────────────────────────

@test "mokerlink-restore: missing --transport exits non-zero" {
    run bash "${BIN_DIR}/mokerlink-restore" \
        --config "${CFG}" --host 192.168.2.1
    [ "$status" -ne 0 ]
    [[ "$output" == *"transport is required"* ]]
}

@test "mokerlink-restore: missing --config exits non-zero" {
    run bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial --port "${FAKE_PORT}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"config file is required"* ]]
}

@test "mokerlink-restore: non-existent --config file exits non-zero" {
    run bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial \
        --config "${TEST_TMPDIR}/no-such-file.cfg" \
        --port "${FAKE_PORT}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "mokerlink-restore: unknown --transport exits non-zero" {
    run bash "${BIN_DIR}/mokerlink-restore" \
        --transport badtransport \
        --config "${CFG}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown transport"* ]]
}

@test "mokerlink-restore: unknown option exits non-zero" {
    run bash "${BIN_DIR}/mokerlink-restore" --no-such-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "mokerlink-restore: unexpected positional argument exits non-zero" {
    run bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial --config "${CFG}" unexpected_arg
    [ "$status" -ne 0 ]
    [[ "$output" == *"unexpected argument"* ]]
}

# ── SSH transport password validation ─────────────────────────────────────────

@test "mokerlink-restore: --transport ssh requires password" {
    run env MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/nonexistent-pw" \
        bash "${BIN_DIR}/mokerlink-restore" \
        --transport ssh \
        --config "${CFG}" \
        --host 192.168.2.1
    [ "$status" -ne 0 ]
    [[ "$output" == *"MOKERLINK_PASSWORD"* ]]
}

@test "mokerlink-restore: --transport ssh-cmd requires password" {
    run env MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/nonexistent-pw" \
        bash "${BIN_DIR}/mokerlink-restore" \
        --transport ssh-cmd \
        --config "${CFG}" \
        --host 192.168.2.1
    [ "$status" -ne 0 ]
    [[ "$output" == *"MOKERLINK_PASSWORD"* ]]
}

@test "mokerlink-restore: --transport serial does not require password" {
    # Serial bootstrap uses factory default admin/admin when no password given.
    run env MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/nonexistent-pw" \
        TFTP_HOST=127.0.0.1 \
        bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial \
        --config "${CFG}" \
        --host 192.168.2.1 \
        --port "${FAKE_PORT}" \
        --no-wait
    # Should pass validation and reach the stub (exit 0).
    [ "$status" -eq 0 ]
}

# ── Serial: auto-detect absent port ───────────────────────────────────────────

@test "mokerlink-restore: --transport serial exits non-zero when no port found" {
    # Override PATH to remove any real serial devices from auto-detect by
    # running in an env with no /dev/cu.usbserial-* or /dev/ttyUSB0.
    # We cannot remove real /dev entries, but we can test the error message
    # by providing a config and omitting --port when no candidates exist.
    # This test is skipped if a real serial port is present on the host.
    for _c in /dev/cu.usbserial-* /dev/ttyUSB0 /dev/ttyACM0; do
        [[ -c "${_c}" ]] && skip "real serial port present; skipping"
    done
    run env MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/nonexistent-pw" \
        bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial \
        --config "${CFG}" \
        --host 192.168.2.1
    [ "$status" -ne 0 ]
    [[ "$output" == *"no serial port found"* ]]
}

# ── --no-reboot / --no-wait flag acceptance ───────────────────────────────────

@test "mokerlink-restore: --no-reboot and --no-wait are accepted" {
    run env TFTP_HOST=127.0.0.1 \
        bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial \
        --config "${CFG}" \
        --port "${FAKE_PORT}" \
        --no-reboot \
        --no-wait
    [ "$status" -eq 0 ]
}

# ── Option aliases ────────────────────────────────────────────────────────────

@test "mokerlink-restore: -t accepted as --transport alias" {
    run env TFTP_HOST=127.0.0.1 \
        bash "${BIN_DIR}/mokerlink-restore" \
        -t serial \
        -c "${CFG}" \
        --port "${FAKE_PORT}" \
        --no-wait
    [ "$status" -eq 0 ]
}

@test "mokerlink-restore: -c accepted as --config alias" {
    run env TFTP_HOST=127.0.0.1 \
        bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial \
        -c "${CFG}" \
        --port "${FAKE_PORT}" \
        --no-wait
    [ "$status" -eq 0 ]
}

@test "mokerlink-restore: MOKERLINK_HOST env used when --host not given" {
    run env MOKERLINK_HOST=192.168.2.1 \
        TFTP_HOST=127.0.0.1 \
        bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial \
        --config "${CFG}" \
        --port "${FAKE_PORT}" \
        --no-wait
    [ "$status" -eq 0 ]
}

@test "mokerlink-restore: --tftp-host accepted and used instead of TFTP_HOST env" {
    run bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial \
        --config "${CFG}" \
        --port "${FAKE_PORT}" \
        --tftp-host 127.0.0.1 \
        --no-wait
    [ "$status" -eq 0 ]
}

@test "mokerlink-restore: --tftp-host overrides TFTP_HOST env var" {
    run env TFTP_HOST=10.0.0.1 \
        bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial \
        --config "${CFG}" \
        --port "${FAKE_PORT}" \
        --tftp-host 127.0.0.1 \
        --no-wait
    [ "$status" -eq 0 ]
}

# ── serial-cmd transport ──────────────────────────────────────────────────────

@test "mokerlink-restore: --transport serial-cmd does not require password" {
    run env MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/nonexistent-pw" \
        bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial-cmd \
        --config "${CFG}" \
        --port "${FAKE_PORT}" \
        --no-wait
    [ "$status" -eq 0 ]
}

@test "mokerlink-restore: --transport serial-cmd exits non-zero when no port found" {
    for _c in /dev/cu.usbserial-* /dev/ttyUSB0 /dev/ttyACM0; do
        [[ -c "${_c}" ]] && skip "real serial port present; skipping"
    done
    run env MOKERLINK_PASSWORD= \
        MOKERLINK_PASSWORD_FILE="${TEST_TMPDIR}/nonexistent-pw" \
        bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial-cmd \
        --config "${CFG}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no serial port found"* ]]
}

@test "mokerlink-restore: --transport serial-cmd invokes set-config-cmd-serial" {
    run bash "${BIN_DIR}/mokerlink-restore" \
        --transport serial-cmd \
        --config "${CFG}" \
        --port "${FAKE_PORT}" \
        --no-wait
    [ "$status" -eq 0 ]
    [[ "$output" == *"stub set-config-cmd-serial"* ]]
}
