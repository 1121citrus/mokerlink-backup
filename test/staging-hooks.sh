#!/usr/bin/env bash
# shellcheck shell=bash

# test/staging-hooks.sh — repo-specific helpers and test implementations
# for the mokerlink-backup staging harness (test/staging).
#
# Called by: test/staging (generated) via `source staging-hooks.sh`
# Provides:  setup_hooks() — docker-run helpers and switch credential resolution
#            test_staging_* — repo-specific test functions
#
# The generated test/staging provides: scan/advise tests, setup(), run_tests(),
# main(). This file provides only what is repo-specific.
#
# Generated harness variable mapping (generated → container env):
#   HOST              → MOKERLINK_HOST
#   REMOTE_USER       → MOKERLINK_USER (default: remote-backup)
#   REMOTE_PASSWORD   → MOKERLINK_PASSWORD
#   REMOTE_PASSWORD_FILE → password file path

# ---------------------------------------------------------------------------
# setup_hooks — defines docker-run helpers used by test functions.
# Called by setup() in the generated harness after credentials are ready.
# Exported env vars from setup(): _aws_cfg_mount, _aws_creds_mount, _scan_tar
# ---------------------------------------------------------------------------
setup_hooks() {
    # Resolve switch password once — prefer REMOTE_PASSWORD, then file.
    local pw_file="${REMOTE_PASSWORD_FILE:-${HOME}/.secrets/mokerlink-password}"
    if [[ -n "${REMOTE_PASSWORD:-}" ]]; then
        switch_password="${REMOTE_PASSWORD}"
    elif [[ -r "${pw_file}" ]]; then
        switch_password=$(cat "${pw_file}")
    else
        switch_password=
    fi
    export switch_password

    # Run mokerlink-backup CLI with switch credentials and the given CLI args.
    run_mokerlink_backup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "MOKERLINK_HOST=${HOST:-}" \
            -e "MOKERLINK_USER=${REMOTE_USER:-remote-backup}" \
            -e "MOKERLINK_PASSWORD=${switch_password}" \
            "${IMAGE}" /usr/local/bin/mokerlink-backup "$@" 2>/dev/null
    }

    # Run the backup script with switch + AWS credentials.
    # shellcheck disable=SC2120  # "$@" accepts optional extra docker flags
    run_backup() {
        local args=()
        _append_aws_mounts args
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "MOKERLINK_HOST=${HOST:-}" \
            -e "MOKERLINK_USER=${REMOTE_USER:-remote-backup}" \
            -e "MOKERLINK_PASSWORD=${switch_password}" \
            -e "AWS_S3_BUCKET_NAME=${S3_BUCKET_NAME:-}" \
            -e "AWS_DRYRUN=${DRYRUN:-true}" \
            -e "COMPRESSION=${COMPRESSION:-none}" \
            "${args[@]}" \
            "$@" \
            "${IMAGE}" /usr/local/bin/backup 2>&1
    }

    # Start the full service container (startup → crond → backup) detached.
    run_service_detached() {
        local args=()
        _append_aws_mounts args
        # shellcheck disable=SC2086
        docker run -d ${DOCKER_RUN_ARGS:-} \
            -e "MOKERLINK_HOST=${HOST:-}" \
            -e "MOKERLINK_USER=${REMOTE_USER:-remote-backup}" \
            -e "MOKERLINK_PASSWORD=${switch_password}" \
            -e "AWS_S3_BUCKET_NAME=${S3_BUCKET_NAME:-}" \
            -e "AWS_DRYRUN=${DRYRUN:-true}" \
            -e "COMPRESSION=${COMPRESSION:-none}" \
            "${args[@]}" \
            "$@" \
            "${IMAGE}"
    }

    export -f run_mokerlink_backup run_backup run_service_detached
}

# _switch_available: returns 0 when HOST and a switch password are set.
# Must be called after setup_hooks() so switch_password is resolved.
_switch_available() {
    [[ -n "${HOST:-}" ]] && [[ -n "${switch_password:-}" ]]
}

# ---------------------------------------------------------------------------
# CLI / smoke tests (no switch or AWS required)
# ---------------------------------------------------------------------------

test_staging_format_invalid() {
    local result=0
    run_mokerlink_backup --format badformat > /dev/null 2>&1 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': exits non-zero for invalid --format value"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero"
        return 1
    fi
}

test_staging_all_excluded() {
    local result=0
    run_mokerlink_backup --no-running --no-startup --no-backup \
        > /dev/null 2>&1 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': exits non-zero when all configs excluded"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero"
        return 1
    fi
}

test_staging_backup_help() {
    local output result=0
    output=$(docker run --rm "${IMAGE}" /usr/local/bin/backup --help 2>&1) \
        || result=$?
    if [[ ${result} -eq 0 ]] && echo "${output}" | grep -qE 'Usage:|SYNOPSIS'; then
        echo "PASS '${FUNCNAME[0]}': backup --help exits 0 and prints usage"
    else
        echo "FAIL '${FUNCNAME[0]}': backup --help failed (exit=${result})"
        return 1
    fi
}

test_staging_backup_no_bucket() {
    local result=0
    docker run --rm "${IMAGE}" /usr/local/bin/backup > /dev/null 2>&1 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': backup without bucket exits non-zero"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero without bucket"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Switch-dependent tests (require HOST + switch password)
# ---------------------------------------------------------------------------

test_staging_default_tar() {
    local tmpdir
    tmpdir=$(mktemp -d)
    run_mokerlink_backup > "${tmpdir}/out.tar" || {
        echo "FAIL '${FUNCNAME[0]}': command exited non-zero"
        rm -rf "${tmpdir}"; return 1
    }
    if ! tar -tf "${tmpdir}/out.tar" > /dev/null 2>&1; then
        echo "FAIL '${FUNCNAME[0]}': output is not a valid tar archive"
        rm -rf "${tmpdir}"; return 1
    fi
    local contents pass=true
    contents=$(tar -tf "${tmpdir}/out.tar")
    rm -rf "${tmpdir}"
    for config in running startup backup; do
        if echo "${contents}" | grep -q "${config}-config-backup.xml"; then
            echo "PASS '${FUNCNAME[0]}': archive contains ${config}-config-backup.xml"
        else
            echo "FAIL '${FUNCNAME[0]}': archive missing ${config}-config-backup.xml"
            pass=false
        fi
    done
    ${pass}
}

test_staging_running_only() {
    local tmpdir
    tmpdir=$(mktemp -d)
    run_mokerlink_backup --running > "${tmpdir}/out.tar" || {
        echo "FAIL '${FUNCNAME[0]}': command exited non-zero"
        rm -rf "${tmpdir}"; return 1
    }
    local contents pass=true
    contents=$(tar -tf "${tmpdir}/out.tar")
    rm -rf "${tmpdir}"
    if echo "${contents}" | grep -q 'running-config-backup.xml'; then
        echo "PASS '${FUNCNAME[0]}': archive contains running-config-backup.xml"
    else
        echo "FAIL '${FUNCNAME[0]}': archive missing running-config-backup.xml"
        pass=false
    fi
    for config in startup backup; do
        if echo "${contents}" | grep -q "${config}-config-backup.xml"; then
            echo "FAIL '${FUNCNAME[0]}': archive should not contain" \
                 "${config}-config-backup.xml"
            pass=false
        else
            echo "PASS '${FUNCNAME[0]}': archive correctly excludes" \
                 "${config}-config-backup.xml"
        fi
    done
    ${pass}
}

test_staging_startup_only() {
    local tmpdir
    tmpdir=$(mktemp -d)
    run_mokerlink_backup --startup > "${tmpdir}/out.tar" || {
        echo "FAIL '${FUNCNAME[0]}': command exited non-zero"
        rm -rf "${tmpdir}"; return 1
    }
    local contents pass=true
    contents=$(tar -tf "${tmpdir}/out.tar")
    rm -rf "${tmpdir}"
    if echo "${contents}" | grep -q 'startup-config-backup.xml'; then
        echo "PASS '${FUNCNAME[0]}': archive contains startup-config-backup.xml"
    else
        echo "FAIL '${FUNCNAME[0]}': archive missing startup-config-backup.xml"
        pass=false
    fi
    for config in running backup; do
        if echo "${contents}" | grep -q "${config}-config-backup.xml"; then
            echo "FAIL '${FUNCNAME[0]}': archive should not contain" \
                 "${config}-config-backup.xml"
            pass=false
        else
            echo "PASS '${FUNCNAME[0]}': archive correctly excludes" \
                 "${config}-config-backup.xml"
        fi
    done
    ${pass}
}

test_staging_backup_only() {
    local tmpdir
    tmpdir=$(mktemp -d)
    run_mokerlink_backup --backup > "${tmpdir}/out.tar" || {
        echo "FAIL '${FUNCNAME[0]}': command exited non-zero"
        rm -rf "${tmpdir}"; return 1
    }
    local contents pass=true
    contents=$(tar -tf "${tmpdir}/out.tar")
    rm -rf "${tmpdir}"
    if echo "${contents}" | grep -q 'backup-config-backup.xml'; then
        echo "PASS '${FUNCNAME[0]}': archive contains backup-config-backup.xml"
    else
        echo "FAIL '${FUNCNAME[0]}': archive missing backup-config-backup.xml"
        pass=false
    fi
    for config in running startup; do
        if echo "${contents}" | grep -q "${config}-config-backup.xml"; then
            echo "FAIL '${FUNCNAME[0]}': archive should not contain" \
                 "${config}-config-backup.xml"
            pass=false
        else
            echo "PASS '${FUNCNAME[0]}': archive correctly excludes" \
                 "${config}-config-backup.xml"
        fi
    done
    ${pass}
}

test_staging_no_running() {
    local tmpdir
    tmpdir=$(mktemp -d)
    run_mokerlink_backup --no-running > "${tmpdir}/out.tar" || {
        echo "FAIL '${FUNCNAME[0]}': command exited non-zero"
        rm -rf "${tmpdir}"; return 1
    }
    local contents pass=true
    contents=$(tar -tf "${tmpdir}/out.tar")
    rm -rf "${tmpdir}"
    if echo "${contents}" | grep -q 'running-config-backup.xml'; then
        echo "FAIL '${FUNCNAME[0]}': archive should not contain running-config-backup.xml"
        pass=false
    else
        echo "PASS '${FUNCNAME[0]}': --no-running correctly excludes running config"
    fi
    for config in startup backup; do
        if echo "${contents}" | grep -q "${config}-config-backup.xml"; then
            echo "PASS '${FUNCNAME[0]}': archive contains ${config}-config-backup.xml"
        else
            echo "FAIL '${FUNCNAME[0]}': archive missing ${config}-config-backup.xml"
            pass=false
        fi
    done
    ${pass}
}

test_staging_format_raw() {
    local output result=0
    output=$(run_mokerlink_backup --running --format raw) || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "FAIL '${FUNCNAME[0]}': command exited non-zero (${result})"
        return 1
    fi
    if echo "${output}" | grep -q '! System Version:'; then
        echo "PASS '${FUNCNAME[0]}': --format raw outputs config text with version marker"
    else
        echo "FAIL '${FUNCNAME[0]}': --format raw output missing '! System Version:' marker"
        return 1
    fi
}

test_staging_name_file() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # shellcheck disable=SC2086
    docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "MOKERLINK_HOST=${HOST:-}" \
        -e "MOKERLINK_USER=${REMOTE_USER:-remote-backup}" \
        -e "MOKERLINK_PASSWORD=${switch_password}" \
        -e "MOKERLINK_BACKUP_NAME_FILE=/name/result" \
        -v "${tmpdir}:/name" \
        "${IMAGE}" /usr/local/bin/mokerlink-backup > /dev/null 2>/dev/null || {
        echo "FAIL '${FUNCNAME[0]}': command exited non-zero"
        rm -rf "${tmpdir}"; return 1
    }
    local name
    name=$(cat "${tmpdir}/result" 2>/dev/null) || {
        echo "FAIL '${FUNCNAME[0]}': name file not written to ${tmpdir}/result"
        rm -rf "${tmpdir}"; return 1
    }
    rm -rf "${tmpdir}"
    if [[ "${name}" == *"-config-backup.tar" ]]; then
        echo "PASS '${FUNCNAME[0]}': name file contains expected tar filename: ${name}"
    else
        echo "FAIL '${FUNCNAME[0]}': unexpected name file contents: '${name}'"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Cron / service-mode tests (require switch + AWS)
# ---------------------------------------------------------------------------

test_staging_backup_direct() {
    printf '  starting backup (AWS_DRYRUN=%s; may take up to 2m)...\n' \
        "${DRYRUN:-true}" >&2

    local tmpfile result=0 elapsed=0
    tmpfile=$(mktemp)
    run_backup > "${tmpfile}" 2>&1 &
    local bgpid=$!
    while kill -0 "${bgpid}" 2>/dev/null; do
        sleep 10
        elapsed=$(( elapsed + 10 ))
        printf '  [%ds] backup in progress...\n' "${elapsed}" >&2
    done
    wait "${bgpid}" && result=0 || result=$?

    local output
    output=$(cat "${tmpfile}")
    rm -f "${tmpfile}"

    if [[ ${result} -ne 0 ]]; then
        echo "FAIL '${FUNCNAME[0]}': backup exited non-zero (${result})"
        printf '%s\n' "${output}" | tail -5 >&2
        return 1
    fi
    if echo "${output}" | grep -q 'finish backup'; then
        echo "PASS '${FUNCNAME[0]}': backup completed in ${elapsed}s" \
             "(AWS_DRYRUN=${DRYRUN:-true})"
    else
        echo "FAIL '${FUNCNAME[0]}': 'finish backup' not found in output"
        printf '%s\n' "${output}" | tail -5 >&2
        return 1
    fi
}

test_staging_cron_fires() {
    local container_id
    container_id=$(run_service_detached -e "CRON_EXPRESSION=* * * * *")
    printf '  container %s started; waiting for first cron backup (up to 4m)...\n' \
        "${container_id:0:12}" >&2

    local result=0
    _wait_for_log_pattern "${container_id}" 'finish backup' 240 || result=$?

    docker stop "${container_id}" > /dev/null 2>&1
    docker rm   "${container_id}" > /dev/null 2>&1

    if [[ ${result} -eq 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': cron backup completed within ${_WAIT_ELAPSED}s" \
             "(AWS_DRYRUN=${DRYRUN:-true})"
    else
        echo "FAIL '${FUNCNAME[0]}': backup did not complete within 240s"
        return 1
    fi
}
