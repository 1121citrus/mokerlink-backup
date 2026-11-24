#!/usr/bin/env bats
# shellcheck shell=bash
# test/14-cfg-to-commands.bats — unit tests for cfg-to-commands.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    TEST_TMPDIR=$(mktemp -d)
    SCRIPT="${REPO_ROOT}/src/bin/cfg-to-commands"

    mkdir -p /usr/local/include/bash
    ln -sfn "${REPO_ROOT}/src/common-functions" \
        /usr/local/include/bash/common-functions

    export REPO_ROOT TEST_TMPDIR SCRIPT
}

teardown() {
    rm -rf "${TEST_TMPDIR:-}"
}

# Helper: run cfg-to-commands on inline config text.
# Usage: run_cfg <<'EOF'
#          config lines...
#        EOF
run_cfg() {
    local input="${TEST_TMPDIR}/input.cfg"
    cat > "${input}"
    bash "${SCRIPT}" "${input}" 2>/dev/null
}

# ── --help ────────────────────────────────────────────────────────────────────

@test "cfg-to-commands: --help exits 0" {
    run bash "${SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── Header and comment stripping ──────────────────────────────────────────────

@test "cfg-to-commands: strips SYSTEM CONFIG FILE header" {
    output=$(run_cfg <<'EOF'
SYSTEM CONFIG FILE ::= BEGIN
system name "test"
EOF
)
    [[ "${output}" != *"SYSTEM CONFIG FILE"* ]]
}

@test "cfg-to-commands: strips comment lines starting with !" {
    output=$(run_cfg <<'EOF'
! System Version: v1.0.0.34
system name "test"
EOF
)
    [[ "${output}" != *"System Version"* ]]
}

@test "cfg-to-commands: strips blank lines" {
    output=$(run_cfg <<'EOF'
system name "test"

system location "rack"
EOF
)
    # Two blank lines should not produce extra output lines.
    local line_count
    line_count=$(echo "${output}" | grep -c 'system' || true)
    [ "${line_count}" -eq 2 ]
}

@test "cfg-to-commands: skips username lines" {    output=$(run_cfg <<'EOF'
username "admin" secret encrypted MjEyMzJmMjk3YTU3YTVhNzQzODk0YTBlNGE4MDFmYzM=
username "" privilege user secret encrypted dGVzdA==
system name "test"
EOF
)
    echo "${output}" | grep -qv '^username'
    echo "${output}" | grep -q 'system name'
}

@test "cfg-to-commands: translates GEn port names to gin" {
    output=$(run_cfg <<'EOF'
interface GE1
 description "test"
!
interface GE28
 description "uplink"
!
EOF
)
    echo "${output}" | grep -q '^interface gi1$'
    echo "${output}" | grep -q '^interface gi28$'
    ! echo "${output}" | grep -q '^interface GE'
}

# ── Preamble and postamble ─────────────────────────────────────────────────────

@test "cfg-to-commands: first output line is configure" {
    output=$(run_cfg <<'EOF'
system name "test"
EOF
)
    first=$(echo "${output}" | head -1)
    [ "${first}" = "configure" ]
}

@test "cfg-to-commands: last two output lines are end then save" {
    output=$(run_cfg <<'EOF'
system name "test"
EOF
)
    second_last=$(echo "${output}" | tail -2 | head -1)
    last=$(echo "${output}" | tail -1)
    [ "${second_last}" = "end" ]
    [ "${last}" = "save" ]
}

# ── CRLF tolerance ────────────────────────────────────────────────────────────

@test "cfg-to-commands: handles CRLF line endings" {
    printf 'system name "test"\r\nvlan 10\r\n name "V10"\r\n!\r\n' \
        > "${TEST_TMPDIR}/crlf.cfg"
    output=$(bash "${SCRIPT}" "${TEST_TMPDIR}/crlf.cfg" 2>/dev/null)
    # Should not contain literal carriage returns in output.
    [[ "${output}" != *$'\r'* ]]
    [[ "${output}" == *'vlan 10'* ]]
}

# ── Flat (non-block) commands ─────────────────────────────────────────────────

@test "cfg-to-commands: ip address is not followed by spurious exit" {
    output=$(run_cfg <<'EOF'
ip address 192.168.2.1 mask 255.255.255.0
!
EOF
)
    # "ip address ..." should appear; the next line should NOT be "exit".
    local after_ip
    after_ip=$(echo "${output}" | grep -A1 'ip address' | tail -1)
    [ "${after_ip}" != "exit" ]
}

@test "cfg-to-commands: voice-vlan lines are not followed by exit" {
    output=$(run_cfg <<'EOF'
voice-vlan oui-table 00:E0:BB "3COM"
voice-vlan oui-table 00:03:6B "Cisco"
!
EOF
)
    local exit_count
    exit_count=$(echo "${output}" | grep -c '^exit$' || true)
    # Zero exits expected: voice-vlan is flat, no sub-mode.
    [ "${exit_count}" -eq 0 ]
}

# ── Block commands ────────────────────────────────────────────────────────────

@test "cfg-to-commands: vlan block emits exit after sub-commands" {
    output=$(run_cfg <<'EOF'
vlan 10
 name "USER"
!
EOF
)
    [[ "${output}" == *$'vlan 10\nname "USER"\nexit'* ]]
}

@test "cfg-to-commands: back-to-back vlan blocks each get an exit" {
    output=$(run_cfg <<'EOF'
vlan 10
 name "V10"
vlan 20
 name "V20"
!
EOF
)
    local exit_count
    exit_count=$(echo "${output}" | grep -c '^exit$')
    [ "${exit_count}" -eq 2 ]
}

@test "cfg-to-commands: interface block emits exit after sub-commands" {
    output=$(run_cfg <<'EOF'
interface GE1
 description "uplink"
 switchport trunk native vlan 10
!
EOF
)
    [[ "${output}" == *"interface gi1"* ]]
    [[ "${output}" == *"description"* ]]
    [[ "${output}" == *"exit"* ]]
}

@test "cfg-to-commands: spanning-tree block emits exit" {
    output=$(run_cfg <<'EOF'
spanning-tree mst configuration
 name "AA:BB:CC:DD:EE:FF"
!
EOF
)
    [[ "${output}" == *"spanning-tree mst configuration"* ]]
    [[ "${output}" == *"exit"* ]]
}

@test "cfg-to-commands: leading space stripped from sub-commands" {
    output=$(run_cfg <<'EOF'
interface GE1
 description "test"
!
EOF
)
    # Sub-command must appear without leading space.
    grep -q '^description "test"$' <<< "${output}"
}

# ── Full config roundtrip ─────────────────────────────────────────────────────

@test "cfg-to-commands: processes start-config.cfg without error" {
    run bash "${SCRIPT}" "${REPO_ROOT}/test/fixtures/switch-1-start-config.cfg.example"
    [ "$status" -eq 0 ]
}

@test "cfg-to-commands: start-config produces configure preamble" {
    output=$(bash "${SCRIPT}" "${REPO_ROOT}/test/fixtures/switch-1-start-config.cfg.example" 2>/dev/null)
    [ "$(echo "${output}" | head -1)" = "configure" ]
}

@test "cfg-to-commands: start-config produces 28 interface blocks" {
    output=$(bash "${SCRIPT}" "${REPO_ROOT}/test/fixtures/switch-1-start-config.cfg.example" 2>/dev/null)
    local count
    count=$(echo "${output}" | grep -c '^interface gi')
    [ "${count}" -eq 28 ]
}

@test "cfg-to-commands: start-config produces correct exit count" {
    output=$(bash "${SCRIPT}" "${REPO_ROOT}/test/fixtures/switch-1-start-config.cfg.example" 2>/dev/null)
    # 9 vlans + 1 spanning-tree + 28 interfaces = 38 exits.
    local count
    count=$(echo "${output}" | grep -c '^exit$')
    [ "${count}" -eq 38 ]
}
