#!/usr/bin/env bats
# test/04-backup-success.bats — test successful backup paths with each compression mode.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/mokerlink-backup:latest}"
    chmod +x "${WHEREAMI}/bin/"*
    export WHEREAMI IMAGE

    run_backup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e AWS_S3_BUCKET_NAME=test-bucket \
            -e MOKERLINK_HOST=fake-host \
            -e MOKERLINK_PASSWORD=testpass \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/bin/get-config:/usr/local/bin/get-config:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/backup 2>&1
    }
    export -f run_backup
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && rm -rf "${TEST_TMPDIR}"
}

@test "no-compression backup begins and finishes" {
    local output
    output=$(run_backup -e COMPRESSION=none)
    echo "output: ${output}"
    [[ "${output}" == *"begin backup"* ]]
    [[ "${output}" == *"finish backup"* ]]
}

@test "zip compression logs and produces .zip extension" {
    local output
    output=$(run_backup -e COMPRESSION=zip)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with zip"* ]]
    [[ "${output}" == *".zip"* ]]
}

@test "bzip2 compression logs and produces .bz2 extension" {
    local output
    output=$(run_backup -e COMPRESSION=bzip2)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with bzip2"* ]]
    [[ "${output}" == *".bz2"* ]]
}

@test "bzip3 compression logs and produces .bz3 extension" {
    local output
    output=$(run_backup -e COMPRESSION=bzip3)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with bzip3"* ]]
    [[ "${output}" == *".bz3"* ]]
}

@test "gzip compression logs and produces .gz extension" {
    local output
    output=$(run_backup -e COMPRESSION=gzip)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with gzip"* ]]
    [[ "${output}" == *".gz"* ]]
}

@test "lzop compression logs and produces .lzo extension" {
    local output
    output=$(run_backup -e COMPRESSION=lzop)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with lzop"* ]]
    [[ "${output}" == *".lzo"* ]]
}

@test "pigz compression logs and produces .pgz extension" {
    local output
    output=$(run_backup -e COMPRESSION=pigz)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with pigz"* ]]
    [[ "${output}" == *".pgz"* ]]
}

@test "pixz compression logs and produces .pxz extension" {
    local output
    output=$(run_backup -e COMPRESSION=pixz)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with pixz"* ]]
    [[ "${output}" == *".pxz"* ]]
}

@test "xz compression logs and produces .xz extension" {
    local output
    output=$(run_backup -e COMPRESSION=xz)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with lzma/xz"* ]]
    [[ "${output}" == *".xz"* ]]
}

@test "exits non-zero for unsupported compression algorithm" {
    run run_backup -e COMPRESSION=invalid
    [ "$status" -ne 0 ]
}

@test "archive contains running-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_backup -e COMPRESSION=none -v "${TEST_TMPDIR}:/output" > /dev/null
    local tarfile
    tarfile=$(find "${TEST_TMPDIR}" -name '*.tar' | head -1)
    echo "tarfile: ${tarfile}"
    local contents
    contents=$(tar -tf "${tarfile}")
    echo "archive contents: ${contents}"
    echo "${contents}" | grep -q 'running-config-backup.xml'
}

@test "archive contains startup-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_backup -e COMPRESSION=none -v "${TEST_TMPDIR}:/output" > /dev/null
    local tarfile
    tarfile=$(find "${TEST_TMPDIR}" -name '*.tar' | head -1)
    local contents
    contents=$(tar -tf "${tarfile}")
    echo "archive contents: ${contents}"
    echo "${contents}" | grep -q 'startup-config-backup.xml'
}

@test "archive contains backup-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_backup -e COMPRESSION=none -v "${TEST_TMPDIR}:/output" > /dev/null
    local tarfile
    tarfile=$(find "${TEST_TMPDIR}" -name '*.tar' | head -1)
    local contents
    contents=$(tar -tf "${tarfile}")
    echo "archive contents: ${contents}"
    echo "${contents}" | grep -q 'backup-config-backup.xml'
}
