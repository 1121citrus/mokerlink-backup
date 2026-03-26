#!/usr/bin/env bats
# test/02-mokerlink-backup.bats — test src/bin/mokerlink-backup directly.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/mokerlink-backup:latest}"
    chmod +x "${WHEREAMI}/bin/"*
    export WHEREAMI IMAGE

    # Run mokerlink-backup; extra docker flags go before IMAGE.
    run_mokerlink_backup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e MOKERLINK_HOST=fake-host \
            -e MOKERLINK_PASSWORD=testpass \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/bin/get-config:/usr/local/bin/get-config:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/mokerlink-backup 2>/dev/null
    }

    # Run mokerlink-backup passing CLI arguments to the command (not to docker).
    run_mokerlink_backup_args() {
        local cmd_args=("$@")
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e MOKERLINK_HOST=fake-host \
            -e MOKERLINK_PASSWORD=testpass \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/bin/get-config:/usr/local/bin/get-config:ro" \
            "${IMAGE}" /usr/local/bin/mokerlink-backup "${cmd_args[@]}" 2>/dev/null
    }

    export -f run_mokerlink_backup
    export -f run_mokerlink_backup_args
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && rm -rf "${TEST_TMPDIR}"
}

# ── Required-variable validation ─────────────────────────────────────────────

@test "exits non-zero when neither MOKERLINK_HOST nor TAILSCALE_HOST is set" {
    run run_mokerlink_backup -e MOKERLINK_HOST= -e TAILSCALE_HOST=
    [ "$status" -ne 0 ]
}

@test "TAILSCALE_HOST accepted as fallback when MOKERLINK_HOST is unset" {
    run run_mokerlink_backup -e MOKERLINK_HOST= -e TAILSCALE_HOST=tailscale-host
    [ "$status" -eq 0 ]
}

@test "exits non-zero when no password is available" {
    run run_mokerlink_backup \
        -e MOKERLINK_PASSWORD= \
        -e MOKERLINK_PASSWORD_FILE=/nonexistent
    [ "$status" -ne 0 ]
}

# ── XML output ────────────────────────────────────────────────────────────────

@test "stdout is a valid tar archive" {
    local archive
    archive=$(run_mokerlink_backup)
    echo "checking tar validity"
    echo "${archive}" | tar -t > /dev/null
}

@test "name file is written with expected filename" {
    TEST_TMPDIR=$(mktemp -d)
    run run_mokerlink_backup \
        -e MOKERLINK_BACKUP_NAME_FILE=/name/result \
        -v "${TEST_TMPDIR}:/name"
    [ "$status" -eq 0 ]
    local name
    name=$(cat "${TEST_TMPDIR}/result")
    echo "name: ${name}"
    [[ "${name}" == *"-config-backup.tar" ]]
}

@test "archive contains running-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_mokerlink_backup > "${TEST_TMPDIR}/out.tar"
    local contents
    contents=$(tar -tf "${TEST_TMPDIR}/out.tar")
    echo "archive contents: ${contents}"
    echo "${contents}" | grep -q 'running-config-backup.xml'
}

@test "archive contains startup-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_mokerlink_backup > "${TEST_TMPDIR}/out.tar"
    local contents
    contents=$(tar -tf "${TEST_TMPDIR}/out.tar")
    echo "archive contents: ${contents}"
    echo "${contents}" | grep -q 'startup-config-backup.xml'
}

@test "archive contains backup-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_mokerlink_backup > "${TEST_TMPDIR}/out.tar"
    local contents
    contents=$(tar -tf "${TEST_TMPDIR}/out.tar")
    echo "archive contents: ${contents}"
    echo "${contents}" | grep -q 'backup-config-backup.xml'
}

# ── CLI flag tests ────────────────────────────────────────────────────────────

@test "--help exits 0 and prints usage" {
    local output
    output=$(run_mokerlink_backup_args --help 2>&1)
    echo "output: ${output}"
    [ "$?" -eq 0 ]
    [[ "${output}" == *"Usage:"* ]]
}

@test "--version exits 0" {
    run run_mokerlink_backup_args --version
    [ "$status" -eq 0 ]
}

@test "-H flag accepted as host" {
    run run_mokerlink_backup_args -H flag-host
    [ "$status" -eq 0 ]
}

@test "--running includes only running-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_mokerlink_backup_args --running > "${TEST_TMPDIR}/out.tar"
    local contents
    contents=$(tar -tf "${TEST_TMPDIR}/out.tar")
    echo "archive contents: ${contents}"
    echo "${contents}" | grep -q 'running-config-backup.xml'
    ! echo "${contents}" | grep -q 'startup-config-backup.xml'
    ! echo "${contents}" | grep -q 'backup-config-backup.xml'
}

@test "--startup includes only startup-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_mokerlink_backup_args --startup > "${TEST_TMPDIR}/out.tar"
    local contents
    contents=$(tar -tf "${TEST_TMPDIR}/out.tar")
    echo "archive contents: ${contents}"
    echo "${contents}" | grep -q 'startup-config-backup.xml'
    ! echo "${contents}" | grep -q 'running-config-backup.xml'
    ! echo "${contents}" | grep -q 'backup-config-backup.xml'
}

@test "--backup includes only backup-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_mokerlink_backup_args --backup > "${TEST_TMPDIR}/out.tar"
    local contents
    contents=$(tar -tf "${TEST_TMPDIR}/out.tar")
    echo "archive contents: ${contents}"
    echo "${contents}" | grep -q 'backup-config-backup.xml'
    ! echo "${contents}" | grep -q 'running-config-backup.xml'
    ! echo "${contents}" | grep -q 'startup-config-backup.xml'
}

@test "--no-running excludes running-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_mokerlink_backup_args --no-running > "${TEST_TMPDIR}/out.tar"
    local contents
    contents=$(tar -tf "${TEST_TMPDIR}/out.tar")
    echo "archive contents: ${contents}"
    ! echo "${contents}" | grep -q 'running-config-backup.xml'
    echo "${contents}" | grep -q 'startup-config-backup.xml'
    echo "${contents}" | grep -q 'backup-config-backup.xml'
}

@test "--no-startup excludes startup-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_mokerlink_backup_args --no-startup > "${TEST_TMPDIR}/out.tar"
    local contents
    contents=$(tar -tf "${TEST_TMPDIR}/out.tar")
    echo "archive contents: ${contents}"
    ! echo "${contents}" | grep -q 'startup-config-backup.xml'
    echo "${contents}" | grep -q 'running-config-backup.xml'
    echo "${contents}" | grep -q 'backup-config-backup.xml'
}

@test "--no-backup excludes backup-config-backup.xml" {
    TEST_TMPDIR=$(mktemp -d)
    run_mokerlink_backup_args --no-backup > "${TEST_TMPDIR}/out.tar"
    local contents
    contents=$(tar -tf "${TEST_TMPDIR}/out.tar")
    echo "archive contents: ${contents}"
    ! echo "${contents}" | grep -q 'backup-config-backup.xml'
    echo "${contents}" | grep -q 'running-config-backup.xml'
    echo "${contents}" | grep -q 'startup-config-backup.xml'
}

@test "--format raw outputs config text" {
    local output
    output=$(run_mokerlink_backup_args --running --format raw)
    echo "output: ${output}"
    [[ "${output}" == *"System Version:"* ]]
}

@test "exits non-zero for unknown --format value" {
    run run_mokerlink_backup_args --format badformat
    [ "$status" -ne 0 ]
}

@test "exits non-zero for unknown option" {
    run run_mokerlink_backup_args --no-such-option
    [ "$status" -ne 0 ]
}

@test "exits non-zero when all configs excluded" {
    run run_mokerlink_backup_args --no-running --no-startup --no-backup
    [ "$status" -ne 0 ]
}
