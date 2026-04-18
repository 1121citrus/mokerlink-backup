#!/usr/bin/env bats
# test/06-healthcheck.bats — test all healthcheck scenarios.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/mokerlink-backup:latest}"
    export WHEREAMI IMAGE

    # shellcheck disable=SC2317
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
    # shellcheck disable=SC2016
    script+=' > /var/spool/cron/crontabs/$(id -un)'
    # shellcheck disable=SC2016
    script+=' && chmod 0600 /var/spool/cron/crontabs/$(id -un)'
    script+=' && crond -l 2 && sleep 0.5'
    script+=' && /usr/local/bin/healthcheck'
    run run_healthcheck "${script}" \
        --tmpfs /var/spool/cron/crontabs:uid=10001,gid=10001,mode=0700
    [ "$status" -eq 0 ]
}

@test "healthcheck exits non-zero when crontab is missing" {
    local script='crond -l 2 && sleep 0.5 && /usr/local/bin/healthcheck'
    run run_healthcheck "${script}"
    [ "$status" -ne 0 ]
}

# ── Sentinel-file tests ───────────────────────────────────────────────────────

_crond_setup='mkdir -p /var/spool/cron/crontabs'
_crond_setup+=' && printf "%s\n" "* * * * * /usr/local/bin/backup 2>&1"'
# shellcheck disable=SC2016
_crond_setup+=' > /var/spool/cron/crontabs/$(id -un)'
# shellcheck disable=SC2016
_crond_setup+=' && chmod 0600 /var/spool/cron/crontabs/$(id -un)'
_crond_setup+=' && crond -l 2 && sleep 0.5'

@test "healthcheck reports healthy when no sentinel file exists" {
    local script="${_crond_setup}"
    script+=' && BACKUP_SENTINEL_FILE=/tmp/no-such-sentinel /usr/local/bin/healthcheck'
    run run_healthcheck "${script}" \
        --tmpfs /var/spool/cron/crontabs:uid=10001,gid=10001,mode=0700
    [ "$status" -eq 0 ]
}

@test "healthcheck reports healthy when sentinel file is fresh" {
    local script="${_crond_setup}"
    script+=' && touch /tmp/mokerlink-backup-last-success'
    script+=' && /usr/local/bin/healthcheck'
    run run_healthcheck "${script}" \
        --tmpfs /var/spool/cron/crontabs:uid=10001,gid=10001,mode=0700
    [ "$status" -eq 0 ]
}

@test "healthcheck reports unhealthy when sentinel file is too old" {
    local script="${_crond_setup}"
    script+=' && touch -t 202001010000 /tmp/mokerlink-backup-last-success'
    script+=' && /usr/local/bin/healthcheck'
    run run_healthcheck "${script}" \
        --tmpfs /var/spool/cron/crontabs:uid=10001,gid=10001,mode=0700
    [ "$status" -ne 0 ]
}
