#!/usr/bin/env bats
# shellcheck shell=bash
# test/13-set-config-ssh.bats — static-analysis tests for set-config-ssh.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    SCRIPT="${REPO_ROOT}/src/bin/set-config-ssh"
    export REPO_ROOT SCRIPT
}

# ── SSH flags (must match get-config exactly) ─────────────────────────────────

@test "set-config-ssh: ignores user ssh config (-F /dev/null)" {
    grep -q '\-F /dev/null' "${SCRIPT}"
}

@test "set-config-ssh: disables strict host key checking" {
    grep -q 'StrictHostKeyChecking=no' "${SCRIPT}"
}

@test "set-config-ssh: disables known-hosts file" {
    grep -q 'UserKnownHostsFile=/dev/null' "${SCRIPT}"
}

@test "set-config-ssh: enables legacy ssh-rsa host key algorithm" {
    grep -q 'HostKeyAlgorithms=+ssh-rsa' "${SCRIPT}"
}

@test "set-config-ssh: enables legacy ssh-rsa pubkey algorithm" {
    grep -q 'PubkeyAcceptedAlgorithms=+ssh-rsa' "${SCRIPT}"
}

# ── Security: credentials not in positional args ──────────────────────────────

@test "set-config-ssh: password passed via env var not positional arg" {
    grep -q 'EXPECT_PASSWORD' "${SCRIPT}"
}

@test "set-config-ssh: password env var is required (not defaulted)" {
    grep -q 'EXPECT_PASSWORD:?' "${SCRIPT}"
}

@test "set-config-ssh: uses single-quoted heredoc to protect Tcl vars" {
    grep -q "'__END_OF_SCRIPT__'" "${SCRIPT}"
}

# ── Expect session behaviour ──────────────────────────────────────────────────

@test "set-config-ssh: disables output pager with terminal length 0" {
    grep -q 'terminal length 0' "${SCRIPT}"
}

@test "set-config-ssh: issues copy tftp command" {
    grep -q 'copy tftp://' "${SCRIPT}"
}

@test "set-config-ssh: targets startup-config" {
    grep -q 'startup-config' "${SCRIPT}"
}

@test "set-config-ssh: handles Do you want to reboot now prompt" {
    grep -q 'Do you want to reboot now' "${SCRIPT}"
}

@test "set-config-ssh: detects TFTP Error response" {
    grep -q '"Error"' "${SCRIPT}"
}

@test "set-config-ssh: performs two-level exit on no-reboot path" {
    # In the Tcl heredoc, exit commands use send -- "exit\r".
    # grep needs \\r to match the literal backslash-r in the file.
    grep -q 'exit\\r' "${SCRIPT}"
}
