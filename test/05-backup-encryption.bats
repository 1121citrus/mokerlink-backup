#!/usr/bin/env bats
# test/05-backup-encryption.bats — test GPG encryption paths in src/bin/backup.
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
            -e COMPRESSION=none \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/bin/get-config:/usr/local/bin/get-config:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/backup 2>&1
    }
    export -f run_backup
}

@test "GPG encrypts when GPG_PASSPHRASE env var is set" {
    local output
    output=$(run_backup -e GPG_PASSPHRASE=test-passphrase)
    echo "output: ${output}"
    [[ "${output}" == *"encrypting backup"* ]]
    [[ "${output}" == *".gpg"* ]]
}

@test "GPG encrypts when passphrase contains spaces" {
    local output
    output=$(run_backup -e "GPG_PASSPHRASE=pass with spaces")
    echo "output: ${output}"
    [[ "${output}" == *"encrypting backup"* ]]
    [[ "${output}" == *".gpg"* ]]
}

@test "GPG encrypts when GPG_PASSPHRASE_FILE is readable" {
    local output
    output=$(run_backup -e GPG_PASSPHRASE_FILE=/test/fixtures/gpg-passphrase)
    echo "output: ${output}"
    [[ "${output}" == *"encrypting backup"* ]]
    [[ "${output}" == *".gpg"* ]]
}

@test "no GPG encryption when no passphrase is available" {
    local output
    output=$(run_backup -e GPG_PASSPHRASE= -e GPG_PASSPHRASE_FILE=/nonexistent)
    echo "output: ${output}"
    [[ "${output}" != *"encrypting backup"* ]]
    [[ "${output}" != *".gpg"* ]]
}
