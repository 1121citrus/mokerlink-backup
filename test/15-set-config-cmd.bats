#!/usr/bin/env bats
# shellcheck shell=bash
# test/15-set-config-cmd.bats — static-analysis tests for set-config-cmd.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    SCRIPT="${REPO_ROOT}/src/bin/set-config-cmd"
    export REPO_ROOT SCRIPT
}

# ── SSH flags (must match get-config and set-config-ssh) ──────────────────────

@test "set-config-cmd: ignores user ssh config (-F /dev/null)" {
    grep -q '\-F /dev/null' "${SCRIPT}"
}

@test "set-config-cmd: disables strict host key checking" {
    grep -q 'StrictHostKeyChecking=no' "${SCRIPT}"
}

@test "set-config-cmd: disables known-hosts file" {
    grep -q 'UserKnownHostsFile=/dev/null' "${SCRIPT}"
}

@test "set-config-cmd: enables legacy ssh-rsa algorithms" {
    grep -q 'HostKeyAlgorithms=+ssh-rsa' "${SCRIPT}"
    grep -q 'PubkeyAcceptedAlgorithms=+ssh-rsa' "${SCRIPT}"
}

# ── Security ──────────────────────────────────────────────────────────────────

@test "set-config-cmd: password passed via env var not positional arg" {
    grep -q 'EXPECT_PASSWORD' "${SCRIPT}"
}

@test "set-config-cmd: password env var is required (not defaulted)" {
    grep -q 'EXPECT_PASSWORD:?' "${SCRIPT}"
}

@test "set-config-cmd: uses single-quoted heredoc to protect Tcl vars" {
    grep -q "'__END_OF_SCRIPT__'" "${SCRIPT}"
}

# ── Command replay behaviour ──────────────────────────────────────────────────

@test "set-config-cmd: disables output pager" {
    grep -q 'terminal length 0' "${SCRIPT}"
}

@test "set-config-cmd: iterates over command list with foreach" {
    grep -q 'foreach' "${SCRIPT}"
}

@test "set-config-cmd: waits for prompt after each command" {
    grep -q 'expect -re' "${SCRIPT}"
}

@test "set-config-cmd: prompt pattern covers config sub-mode (ends in )#)" {
    grep -q ')#' "${SCRIPT}"
}

@test "set-config-cmd: skips blank command lines" {
    grep -q 'string trim' "${SCRIPT}"
}

@test "set-config-cmd: default do_reboot is n (no automatic reboot)" {
    grep -q 'EXPECT_REBOOT:-n' "${SCRIPT}"
}

# ── Connection error handling ─────────────────────────────────────────────────

@test "set-config-cmd: eof arm handles SSH connection closed before login" {
    grep -q 'eof' "${SCRIPT}"
}

@test "set-config-cmd: eof arm emits error about SSH being enabled" {
    grep -q 'SSH.*enabled' "${SCRIPT}"
}

@test "set-config-cmd: timeout arm handles no login prompt" {
    grep -q 'timed out waiting for SSH login prompt' "${SCRIPT}"
}
