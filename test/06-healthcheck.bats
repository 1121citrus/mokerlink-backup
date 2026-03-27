#!/usr/bin/env bats
# test/06-healthcheck.bats — test all healthcheck scenarios.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/mokerlink-backup:latest}"
    export WHEREAMI IMAGE

    run_healthcheck() {
        local script=$1; shift
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            --entrypoint /usr/bin/env \
            -v "${WHEREAMI}/bin/get-config:/usr/local/bin/get-config:ro" \
            "$@" \
            "${IMAGE}" \
            bash -c "${script}" > /dev/null 2>&1
    }
    export -f run_healthcheck
}

@test "healthcheck exits non-zero when crond is absent" {
    run run_healthcheck "/usr/local/bin/healthcheck"
    [ "$status" -ne 0 ]
}

@test "healthcheck exits 0 with crond running and crontab configured" {
    local script
    script='mkdir -p /var/spool/cron/crontabs'
    script+=' && printf "%s\n" "* * * * * /usr/local/bin/backup 2>&1"'
    script+=' > /var/spool/cron/crontabs/$(id -un)'
    script+=' && chmod 0600 /var/spool/cron/crontabs/$(id -un)'
    script+=' && crond -l 2 && sleep 0.5'
    script+=' && /usr/local/bin/healthcheck'
    run run_healthcheck "${script}"
    [ "$status" -eq 0 ]
}

@test "healthcheck exits non-zero when crontab is missing" {
    local script='crond -l 2 && sleep 0.5 && /usr/local/bin/healthcheck'
    run run_healthcheck "${script}"
    [ "$status" -ne 0 ]
}
