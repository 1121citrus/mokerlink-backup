#!/usr/bin/env bats
# test/01-build.bats — verify build script CLI option coverage.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    BUILD="${REPO_ROOT}/build"
    STAGING="${REPO_ROOT}/test/staging"
}

@test "build --help lists --advice option" {
    local output
    output=$("${BUILD}" --help 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"--advice"* ]]
}

@test "build --help lists --cache option" {
    local output
    output=$("${BUILD}" --help 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"--cache CACHE_RULES"* ]]
}

@test "build --advice scout enables Scout advisement stage" {
    local output
    output=$("${BUILD}" --advice scout --dry-run --no-lint --no-test --no-scan 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"Stage 5b: Advise (Scout)"* ]]
}

@test "build --advise Dive enables Dive advisement stage" {
    local output
    output=$("${BUILD}" --advise Dive --dry-run --no-lint --no-test --no-scan 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"Stage 5c: Advise (Dive)"* ]]
}

@test "build --advise DIVE enables Dive advisement stage" {
    local output
    output=$("${BUILD}" --advise DIVE --dry-run --no-lint --no-test --no-scan 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"Stage 5c: Advise (Dive)"* ]]
}

@test "build --advise none disables all advisements" {
    run "${BUILD}" --advise none --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "${output}" != *"Stage 5a"* ]]
    [[ "${output}" != *"Stage 5b"* ]]
    [[ "${output}" != *"Stage 5c"* ]]
    [[ "${output}" != *"Stage 5d"* ]]
}

@test "build --advise NONE disables all advisements" {
    run "${BUILD}" --advise NONE --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "${output}" != *"Stage 5a"* ]]
    [[ "${output}" != *"Stage 5b"* ]]
    [[ "${output}" != *"Stage 5c"* ]]
    [[ "${output}" != *"Stage 5d"* ]]
}

@test "build --advice none disables all advisements" {
    run "${BUILD}" --advice none --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "${output}" != *"Stage 5a"* ]]
    [[ "${output}" != *"Stage 5b"* ]]
    [[ "${output}" != *"Stage 5c"* ]]
    [[ "${output}" != *"Stage 5d"* ]]
}

@test "build --no-advise disables all advisements" {
    run "${BUILD}" --no-advise --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "${output}" != *"Stage 5a"* ]]
    [[ "${output}" != *"Stage 5b"* ]]
    [[ "${output}" != *"Stage 5c"* ]]
    [[ "${output}" != *"Stage 5d"* ]]
}

@test "build --advise coverage enables Coverage advisement stage" {
    local output
    output=$("${BUILD}" --advise coverage --dry-run --no-lint --no-test --no-scan 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"Stage 5d: Coverage"* ]]
}

@test "build --advise all enables all advisement stages" {
    run "${BUILD}" --advise all --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "${output}" == *"Stage 5a: Advise (Grype)"* ]]
    [[ "${output}" == *"Stage 5b: Advise (Scout)"* ]]
    [[ "${output}" == *"Stage 5c: Advise (Dive)"* ]]
    [[ "${output}" == *"Stage 5d: Coverage"* ]]
}

@test "build --advise scout,dive enables Scout and Dive but not Coverage" {
    run "${BUILD}" --advise scout,dive --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "${output}" == *"Stage 5b: Advise (Scout)"* ]]
    [[ "${output}" == *"Stage 5c: Advise (Dive)"* ]]
    [[ "${output}" != *"Stage 5d"* ]]
}

@test "build --advise rejects unknown advisement" {
    run "${BUILD}" --advise unknown --dry-run
    [ "$status" -eq 1 ]
    [[ "${output}" == *"Unknown advisement"* ]]
}

@test "build defaults to no advisory scans" {
    run "${BUILD}" --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "${output}" != *"Stage 5a"* ]]
    [[ "${output}" != *"Stage 5b"* ]]
    [[ "${output}" != *"Stage 5c"* ]]
    [[ "${output}" != *"Stage 5d"* ]]
}

@test "build --cache reset=all resets Trivy DB" {
    local output
    output=$("${BUILD}" --cache "reset=all" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"Cache: reset Trivy DB"* ]]
}

@test "build --cache reset=all resets Grype DB" {
    local output
    output=$("${BUILD}" --cache "reset=all" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"Cache: reset Grype DB"* ]]
}

@test "build --cache Reset=All resets both caches" {
    local output
    output=$("${BUILD}" --cache "Reset=All" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"Cache: reset Trivy DB"* ]]
    [[ "${output}" == *"Cache: reset Grype DB"* ]]
}

@test "build --cache Skip-Update=TrIvY skips Trivy DB update" {
    run "${BUILD}" --cache "Skip-Update=TrIvY" --dry-run --no-lint --no-test
    [ "$status" -eq 0 ]
    echo "output: ${output}"
    [[ "${output}" == *"Trivy DB update skipped"* ]]
}

@test "test/staging --help lists --scan option" {
    local output
    output=$("${STAGING}" --help 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"--scan"* ]]
}

@test "test/staging --help lists --advise option" {
    local output
    output=$("${STAGING}" --help 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"--advise"* ]]
}

@test "test/staging --help lists --bucket option" {
    local output
    output=$("${STAGING}" --help 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"--bucket"* ]]
}

@test "test/staging --help lists --dryrun option" {
    local output
    output=$("${STAGING}" --help 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"--dryrun"* ]]
}

@test "test/staging --help lists --skip-e2e option" {
    local output
    output=$("${STAGING}" --help 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"--skip-e2e"* ]]
}

@test "test/staging --help lists --test option" {
    local output
    output=$("${STAGING}" --help 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"--test"* ]]
}
