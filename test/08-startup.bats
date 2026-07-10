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

# ── Healthcheck startup marker ───────────────────────────────────────────────
#
# healthcheck's grace-period check reads HEALTHCHECK_STARTUP_FILE to tell
# "just started, first backup hasn't run yet" apart from "actually stuck".
# Mounts a stubbed supercronic so the scheduler-mode handoff exits instead
# of hanging the container.

@test "startup touches the healthcheck startup marker before the supercronic handoff" {
    # shellcheck disable=SC2086
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e HEALTHCHECK_STARTUP_FILE=/tmp/test-startup-marker \
        -v "${BATS_TEST_DIRNAME}/bin/supercronic:/usr/local/bin/supercronic:ro" \
        "${IMAGE}" \
        bash -c '/usr/local/bin/startup >/dev/null 2>&1; test -f /tmp/test-startup-marker && echo MARKER_EXISTS || echo MARKER_MISSING'
    [ "$status" -eq 0 ]
    [[ "${output}" == *"MARKER_EXISTS"* ]]
}
