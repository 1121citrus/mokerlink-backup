#!/usr/bin/env bats
# test/03-backup-required-vars.bats — test required-variable validation.
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
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/bin/get-config:/usr/local/bin/get-config:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/backup 2>&1
    }
    export -f run_backup
}

@test "exits non-zero when AWS_S3_BUCKET_NAME is unset" {
    run run_backup \
        -e MOKERLINK_HOST=fake-host \
        -e MOKERLINK_PASSWORD=foo
    [ "$status" -ne 0 ]
}

@test "exits non-zero when MOKERLINK_HOST and TAILSCALE_HOST are unset" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e MOKERLINK_PASSWORD=foo
    [ "$status" -ne 0 ]
}

@test "exits non-zero when neither password nor password file is provided" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e MOKERLINK_HOST=fake-host \
        -e MOKERLINK_PASSWORD= \
        -e MOKERLINK_PASSWORD_FILE=/nonexistent
    [ "$status" -ne 0 ]
}

@test "TAILSCALE_HOST used as fallback when MOKERLINK_HOST is unset" {
    run run_backup \
        -e MOKERLINK_HOST= \
        -e TAILSCALE_HOST=tailscale-host \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e MOKERLINK_PASSWORD=foo
    [ "$status" -eq 0 ]
}

@test "reads password from MOKERLINK_PASSWORD_FILE" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e MOKERLINK_HOST=fake-host \
        -e MOKERLINK_PASSWORD= \
        -e MOKERLINK_PASSWORD_FILE=/test/fixtures/gpg-passphrase \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro"
    [ "$status" -eq 0 ]
}
