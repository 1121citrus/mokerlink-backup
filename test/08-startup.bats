#!/usr/bin/env bats
# test/08-startup.bats — test startup script CLI options.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    IMAGE="${IMAGE:-1121citrus/mokerlink-backup:latest}"
    export IMAGE

    # shellcheck disable=SC2317
    run_startup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            "${IMAGE}" /usr/local/bin/startup "$@" 2>&1
    }
    export -f run_startup
}

@test "startup --help exits 0 and prints SYNOPSIS" {
    run run_startup --help
    [ "$status" -eq 0 ]
    [[ "${output}" == *"SYNOPSIS"* ]]
}

@test "startup --version exits 0" {
    run run_startup --version
    [ "$status" -eq 0 ]
}

@test "startup rejects unknown options" {
    run run_startup --no-such-option
    [ "$status" -ne 0 ]
}
