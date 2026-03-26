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
