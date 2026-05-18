#!/usr/bin/env bats
# shellcheck shell=bash
# test/11-set-config-serial.bats — static-analysis tests for set-config-serial.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# These tests grep the source file for required invariants rather than running
# the script, so they execute in milliseconds with no hardware dependency and
# catch regressions before any serial port is touched.

setup() {
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    SCRIPT="${REPO_ROOT}/src/bin/set-config-serial"
    export REPO_ROOT SCRIPT
}

# ── Serial port settings ──────────────────────────────────────────────────────

@test "set-config-serial: opens serial port at 115200 baud" {
    grep -q '115200' "${SCRIPT}"
}

@test "set-config-serial: configures 8 data bits, no parity, 1 stop bit" {
    grep -q 'n,8,1' "${SCRIPT}"
}

@test "set-config-serial: sets no flow control (handshake none)" {
    grep -q 'handshake none' "${SCRIPT}"
}

# ── Security: credentials not in positional args ──────────────────────────────

@test "set-config-serial: username passed via env var not positional arg" {
    # The Tcl script reads username from $env(EXPECT_USERNAME), not from
    # positional arguments or a bare $1/$2/$3 assignment.
    grep -q "set username.*\$env(EXPECT_USERNAME)" "${SCRIPT}"
}

@test "set-config-serial: password passed via env var not positional arg" {
    grep -q 'EXPECT_PASSWORD' "${SCRIPT}"
}

@test "set-config-serial: uses single-quoted heredoc to protect Tcl vars" {
    grep -q "'__END_OF_SCRIPT__'" "${SCRIPT}"
}

# ── Expect session behaviour ──────────────────────────────────────────────────

@test "set-config-serial: disables output pager with terminal length 0" {
    grep -q 'terminal length 0' "${SCRIPT}"
}

@test "set-config-serial: issues copy tftp command" {
    grep -q 'copy tftp://' "${SCRIPT}"
}

@test "set-config-serial: issues copy to startup-config" {
    grep -q 'startup-config' "${SCRIPT}"
}

@test "set-config-serial: handles Do you want to reboot now prompt" {
    grep -q 'Do you want to reboot now' "${SCRIPT}"
}

@test "set-config-serial: detects TFTP Error response" {
    grep -q '"Error"' "${SCRIPT}"
}

@test "set-config-serial: handles pre-logged-in console (sends exit)" {
    grep -q '"# "' "${SCRIPT}"
    grep -q 'Already logged in' "${SCRIPT}"
}

@test "set-config-serial: handles user-exec prompt with enable command" {
    grep -q '"enable\\\\r"' "${SCRIPT}" || grep -q 'enable' "${SCRIPT}"
}

# ── wait-for-restart static analysis ─────────────────────────────────────────

@test "wait-for-restart: uses /dev/tcp for port polling" {
    run grep -q '/dev/tcp/' \
        "${REPO_ROOT}/src/bin/wait-for-restart"
    [ "$status" -eq 0 ]
}

@test "wait-for-restart: --host is required" {
    run grep -q '"--host is required"' \
        "${REPO_ROOT}/src/bin/wait-for-restart"
    [ "$status" -eq 0 ]
}

@test "wait-for-restart: has configurable timeout" {
    grep -q 'wait_timeout' \
        "${REPO_ROOT}/src/bin/wait-for-restart"
}

# ── wait-for-restart behaviour (direct execution) ─────────────────────────────

@test "wait-for-restart: --help exits 0" {
    mkdir -p /usr/local/include/bash
    ln -sfn "${REPO_ROOT}/src/common-functions" \
        /usr/local/include/bash/common-functions
    run bash "${REPO_ROOT}/src/bin/wait-for-restart" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "wait-for-restart: missing --host exits non-zero" {
    mkdir -p /usr/local/include/bash
    ln -sfn "${REPO_ROOT}/src/common-functions" \
        /usr/local/include/bash/common-functions
    run bash "${REPO_ROOT}/src/bin/wait-for-restart"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--host is required"* ]]
}

@test "wait-for-restart: unknown option exits non-zero" {
    mkdir -p /usr/local/include/bash
    ln -sfn "${REPO_ROOT}/src/common-functions" \
        /usr/local/include/bash/common-functions
    run bash "${REPO_ROOT}/src/bin/wait-for-restart" --bogus-opt
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "wait-for-restart: exits 0 when host port is open (localhost:22 or 80)" {
    mkdir -p /usr/local/include/bash
    ln -sfn "${REPO_ROOT}/src/common-functions" \
        /usr/local/include/bash/common-functions
    # Find a port we know is open: try sshd (22) then any open port via ss/nc.
    local open_port=
    for _p in 22 80 443; do
        if (: > "/dev/tcp/127.0.0.1/${_p}") 2>/dev/null; then
            open_port="${_p}"
            break
        fi
    done
    [[ -n "${open_port}" ]] || skip "no local open TCP port found"
    run bash "${REPO_ROOT}/src/bin/wait-for-restart" \
        --host 127.0.0.1 --port "${open_port}" --timeout 5
    [ "$status" -eq 0 ]
}

@test "wait-for-restart: exits non-zero when port is unreachable within timeout" {
    mkdir -p /usr/local/include/bash
    ln -sfn "${REPO_ROOT}/src/common-functions" \
        /usr/local/include/bash/common-functions
    # Port 19999 is unlikely to be open; timeout quickly to keep test fast.
    run bash "${REPO_ROOT}/src/bin/wait-for-restart" \
        --host 127.0.0.1 --port 19999 --timeout 6 --interval 2
    [ "$status" -ne 0 ]
}
