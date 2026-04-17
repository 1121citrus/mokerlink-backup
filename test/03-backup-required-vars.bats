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

    # run_backup: extra args are passed to docker (before the image name).
    run_backup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/bin/get-config:/usr/local/bin/get-config:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/backup 2>&1
    }

    # run_backup_args: extra args are appended after the backup command name
    # (i.e., they are CLI arguments to backup, not to docker).
    run_backup_args() {
        local docker_args=()
        local cmd_args=()
        local sep=false
        for arg in "$@"; do
            if [[ "${arg}" == "--" ]]; then sep=true; continue; fi
            if "${sep}"; then cmd_args+=("${arg}"); else docker_args+=("${arg}"); fi
        done
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/bin/get-config:/usr/local/bin/get-config:ro" \
            "${docker_args[@]}" \
            "${IMAGE}" /usr/local/bin/backup "${cmd_args[@]}" 2>&1
    }
    export -f run_backup run_backup_args
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

@test "backup --help exits 0 and prints usage" {
    run run_backup_args -- --help
    [ "$status" -eq 0 ]
    [[ "${output}" == *"SYNOPSIS"* ]]
}

@test "backup --version exits 0" {
    run run_backup_args -- --version
    [ "$status" -eq 0 ]
}

@test "--bucket CLI option provides bucket when AWS_S3_BUCKET_NAME is unset" {
    run run_backup_args \
        -e MOKERLINK_HOST=fake-host \
        -e MOKERLINK_PASSWORD=foo \
        -e AWS_S3_BUCKET_NAME= \
        -- \
        --bucket test-bucket
    [ "$status" -eq 0 ]
}

@test "--aws-config CLI option is accepted" {
    run run_backup_args \
        -e MOKERLINK_HOST=fake-host \
        -e MOKERLINK_PASSWORD=foo \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -- \
        --aws-config /run/secrets/aws-config
    [ "$status" -eq 0 ]
}

@test "--gpg-passphrase-file CLI option is accepted" {
    run run_backup_args \
        -e MOKERLINK_HOST=fake-host \
        -e MOKERLINK_PASSWORD=foo \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        -- \
        --gpg-passphrase-file /test/fixtures/gpg-passphrase
    [ "$status" -eq 0 ]
}

@test "backup rejects unknown options" {
    run run_backup_args -- --no-such-option
    [ "$status" -ne 0 ]
}
