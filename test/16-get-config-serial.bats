#!/usr/bin/env bats
# shellcheck shell=bash
# test/16-get-config-serial.bats — static analysis tests for
# src/bin/get-config-serial.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# All tests grep the source file for structural invariants.  No hardware,
# Docker, or serial device is required.

setup() {
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    SCRIPT="${REPO_ROOT}/src/bin/get-config-serial"
    export REPO_ROOT SCRIPT
}

# ── Serial port configuration ─────────────────────────────────────────────────

@test "get-config-serial: baud rate is 115200" {
    grep -q '115200' "${SCRIPT}"
}

@test "get-config-serial: serial mode is 8N1" {
    grep -q 'n,8,1' "${SCRIPT}"
}

@test "get-config-serial: handshake is none" {
    grep -q 'handshake none' "${SCRIPT}"
}

@test "get-config-serial: fconfigure precedes spawn -open" {
    local fc_line sp_line
    fc_line=$(grep -n 'fconfigure' "${SCRIPT}" | cut -d: -f1 | head -1)
    sp_line=$(grep -n 'spawn -open' "${SCRIPT}" | cut -d: -f1 | head -1)
    [[ "${fc_line}" -lt "${sp_line}" ]]
}

# ── Pager and show command ────────────────────────────────────────────────────

@test "get-config-serial: pager disabled before show command" {
    local pager_line show_line
    pager_line=$(grep -n 'terminal length 0' "${SCRIPT}" | cut -d: -f1 | head -1)
    show_line=$(grep -n 'show \$config_type' "${SCRIPT}" | cut -d: -f1 | head -1)
    [[ "${pager_line}" -lt "${show_line}" ]]
}

@test "get-config-serial: show command uses config_type variable" {
    grep -q 'show \$config_type-config' "${SCRIPT}"
}

# ── Output capture ────────────────────────────────────────────────────────────

@test "get-config-serial: log_user 0 gates output before show command" {
    grep -q 'log_user 0' "${SCRIPT}"
}

@test "get-config-serial: log_user 1 opens capture before expect prompt" {
    grep -q 'log_user 1' "${SCRIPT}"
}

@test "get-config-serial: tail -n +3 strips echo-back lines" {
    grep -q 'tail -n +3' "${SCRIPT}"
}

# ── Credential handling ───────────────────────────────────────────────────────

@test "get-config-serial: username read from EXPECT_USERNAME env var" {
    grep -q 'EXPECT_USERNAME' "${SCRIPT}"
}

@test "get-config-serial: password read from EXPECT_PASSWORD env var" {
    grep -q 'EXPECT_PASSWORD' "${SCRIPT}"
}

@test "get-config-serial: credentials not passed as positional args to expect" {
    # The Tcl script should use $env(EXPECT_PASSWORD), not a positional arg.
    grep -q 'env(EXPECT_PASSWORD)' "${SCRIPT}"
    grep -q 'env(EXPECT_USERNAME)' "${SCRIPT}"
}

# ── Heredoc quoting ───────────────────────────────────────────────────────────

@test "get-config-serial: heredoc delimiter is single-quoted to protect Tcl \$env refs" {
    # A single-quoted delimiter (<<-'__END_...' or <<'__END_...') prevents
    # bash from expanding Tcl $env() references before expect reads them.
    grep -qE "<<-?'__END_OF_SCRIPT__'" "${SCRIPT}"
}

# ── Login sequence ────────────────────────────────────────────────────────────

@test "get-config-serial: prolog uses exp_continue loop to reach login prompt" {
    grep -q 'exp_continue' "${SCRIPT}"
}

@test "get-config-serial: prolog matches any prompt with [>#] regex" {
    grep -q '\[>#\]' "${SCRIPT}"
}

@test "get-config-serial: prolog exits non-zero after too many retries" {
    grep -q 'could not reach login prompt' "${SCRIPT}"
}

@test "get-config-serial: enable command sent when at user-exec prompt" {
    grep -q 'enable' "${SCRIPT}"
}

# ── Common-functions fallback ─────────────────────────────────────────────────

@test "get-config-serial: sources common-functions with relative fallback" {
    grep -q 'bindir.*common-functions' "${SCRIPT}"
    grep -q '/usr/local/include/bash/common-functions' "${SCRIPT}"
}
