#!/usr/bin/env bats
# shellcheck shell=bash
# test/17-tftp-serve.bats — static-analysis and functional tests for tftp-serve.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Static-analysis tests grep the source for required invariants (no hardware
# needed).  Functional tests extract the embedded Python TFTPD code and run
# it on a non-privileged port (15069) to verify the transfer logic end-to-end
# without requiring root or port 69.

setup() {
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    SCRIPT="${REPO_ROOT}/src/bin/tftp-serve"
    TEST_TMPDIR=$(mktemp -d)
    export REPO_ROOT SCRIPT TEST_TMPDIR

    mkdir -p /usr/local/include/bash
    ln -sfn "${REPO_ROOT}/src/common-functions" \
        /usr/local/include/bash/common-functions
}

teardown() {
    rm -rf "${TEST_TMPDIR:-}"
}

# ── Static analysis: RFC 1350 protocol correctness ────────────────────────────

@test "tftp-serve: uses RRQ opcode 1 for read-request detection" {
    grep -q '!= 1' "${SCRIPT}"
}

@test "tftp-serve: uses DATA opcode 3 in struct.pack" {
    grep -q "'!HH', 3," "${SCRIPT}"
}

@test "tftp-serve: uses ACK opcode 4 in response check" {
    grep -q '(4, block' "${SCRIPT}"
}

@test "tftp-serve: uses network byte order in struct calls" {
    grep -q "'!H'" "${SCRIPT}"
    grep -q "'!HH'" "${SCRIPT}"
}

@test "tftp-serve: wraps block number to 16 bits for RFC 1350 rollover" {
    grep -q '& 0xFFFF' "${SCRIPT}"
}

@test "tftp-serve: uses 512-byte TFTP block size" {
    grep -q '512' "${SCRIPT}"
}

# ── Static analysis: transport correctness ────────────────────────────────────

@test "tftp-serve: uses dedicated transfer socket (random TID) per RFC 1350 s4" {
    grep -q 'xfer = socket.socket' "${SCRIPT}"
}

@test "tftp-serve: closes transfer socket after each RRQ" {
    grep -q 'xfer.close()' "${SCRIPT}"
}

@test "tftp-serve: sets SO_REUSEADDR on listening socket" {
    grep -q 'SO_REUSEADDR' "${SCRIPT}"
}

@test "tftp-serve: retransmits DATA up to 3 times on ACK timeout" {
    grep -q 'range(3)' "${SCRIPT}"
}

@test "tftp-serve: exits after one successful transfer" {
    grep -q 'if ok:' "${SCRIPT}"
    grep -q 'return' "${SCRIPT}"
}

# ── Static analysis: reliability ──────────────────────────────────────────────

@test "tftp-serve: handles SIGTERM gracefully" {
    grep -q 'signal.SIGTERM' "${SCRIPT}"
    grep -q 'sys.exit(0)' "${SCRIPT}"
}

@test "tftp-serve: main socket has 1-second recv timeout for responsiveness" {
    grep -q 'sock.settimeout(1.0)' "${SCRIPT}"
}

@test "tftp-serve: transfer socket has 5-second ACK timeout for retransmit" {
    grep -q 'xfer.settimeout(5.0)' "${SCRIPT}"
}

# ── Static analysis: removed backends ────────────────────────────────────────

@test "tftp-serve: does not reference macOS launchctl" {
    run grep -q 'launchctl' "${SCRIPT}"
    [ "$status" -ne 0 ]
}

@test "tftp-serve: does not reference tftpy" {
    run grep -q 'tftpy' "${SCRIPT}"
    [ "$status" -ne 0 ]
}

@test "tftp-serve: does not reference /private/tftpboot" {
    run grep -q '/private/tftpboot' "${SCRIPT}"
    [ "$status" -ne 0 ]
}

# ── CLI argument tests (no root required) ────────────────────────────────────

@test "tftp-serve: --help exits 0 and prints usage" {
    run bash "${SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--file"* ]]
}

@test "tftp-serve: missing --file exits non-zero" {
    run bash "${SCRIPT}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--file is required"* ]]
}

@test "tftp-serve: non-existent --file exits non-zero" {
    run bash "${SCRIPT}" --file "${TEST_TMPDIR}/no-such-file.txt"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "tftp-serve: unknown option exits non-zero" {
    run bash "${SCRIPT}" --no-such-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "tftp-serve: unexpected positional argument exits non-zero" {
    run bash "${SCRIPT}" unexpected_arg
    [ "$status" -ne 0 ]
    [[ "$output" == *"unexpected argument"* ]]
}

@test "tftp-serve: non-root user gets a clear error about port 69" {
    # This test only applies when not already running as root.
    [[ "$(id -u)" -eq 0 ]] && skip "running as root; non-root check not exercised"
    printf 'test\n' > "${TEST_TMPDIR}/dummy.txt"
    run bash "${SCRIPT}" --file "${TEST_TMPDIR}/dummy.txt"
    [ "$status" -ne 0 ]
    [[ "$output" == *"root"* ]]
}

# ── Functional: Python TFTPD end-to-end transfer (no root needed) ────────────

_extract_tftpd_python() {
    # Extract the inline Python server from the bash heredoc in tftp-serve.
    # Uses awk (BSD and busybox compatible) instead of sed address+negation
    # syntax which is GNU-only.
    awk '/^import signal, socket/{p=1} /^__TFTPD__$/{exit} p' \
        "${SCRIPT}"
}

_tftp_client_python() {
    # Minimal RFC 1350 read client: sends RRQ, collects DATA blocks.
    # Args: host port filename outfile
    python3 - "$@" <<'__CLIENT__'
import socket, struct, sys
host, port, name, outpath = sys.argv[1], int(sys.argv[2]), \
    sys.argv[3].encode(), sys.argv[4]
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(5.0)
s.sendto(struct.pack('!H', 1) + name + b'\x00octet\x00', (host, port))
buf, block = b'', 1
while True:
    pkt, addr = s.recvfrom(65536)
    op, blk = struct.unpack('!HH', pkt[:4])
    chunk = pkt[4:]
    buf += chunk
    s.sendto(struct.pack('!HH', 4, block), addr)
    if len(chunk) < 512:
        break
    block += 1
open(outpath, 'wb').write(buf)
__CLIENT__
}

@test "tftp-serve: Python server transfers a single-block file (<512 bytes)" {
    local test_file="${TEST_TMPDIR}/small.txt"
    local received="${TEST_TMPDIR}/small-recv.bin"
    local port=15069

    printf 'hello from tftp-serve\n' > "${test_file}"

    _extract_tftpd_python \
        | python3 - "${test_file}" 127.0.0.1 "${port}" 10 &
    local svr_pid=$!
    sleep 0.5

    _tftp_client_python 127.0.0.1 "${port}" small.txt "${received}"

    kill "${svr_pid}" 2>/dev/null || true
    wait "${svr_pid}" 2>/dev/null || true
    diff "${test_file}" "${received}"
}

@test "tftp-serve: Python server transfers a multi-block file (>512 bytes)" {
    local test_file="${TEST_TMPDIR}/large.txt"
    local received="${TEST_TMPDIR}/large-recv.bin"
    local port=15070

    # 600 bytes: block 1 = 512 bytes, block 2 = 88 bytes (exercises block++)
    python3 -c "print('X' * 600)" > "${test_file}"

    _extract_tftpd_python \
        | python3 - "${test_file}" 127.0.0.1 "${port}" 10 &
    local svr_pid=$!
    sleep 0.5

    _tftp_client_python 127.0.0.1 "${port}" large.txt "${received}"

    kill "${svr_pid}" 2>/dev/null || true
    wait "${svr_pid}" 2>/dev/null || true
    diff "${test_file}" "${received}"
}

@test "tftp-serve: Python server handles exact-512-byte file (empty final block)" {
    local test_file="${TEST_TMPDIR}/exact.bin"
    local received="${TEST_TMPDIR}/exact-recv.bin"
    local port=15071

    # Exactly 512 bytes: transfer requires block 1 (512 bytes) + block 2 (0 bytes)
    python3 -c "import sys; sys.stdout.buffer.write(b'A' * 512)" > "${test_file}"

    _extract_tftpd_python \
        | python3 - "${test_file}" 127.0.0.1 "${port}" 10 &
    local svr_pid=$!
    sleep 0.5

    _tftp_client_python 127.0.0.1 "${port}" exact.bin "${received}"

    kill "${svr_pid}" 2>/dev/null || true
    wait "${svr_pid}" 2>/dev/null || true
    diff "${test_file}" "${received}"
}
