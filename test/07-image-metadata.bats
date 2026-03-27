#!/usr/bin/env bats
# test/07-image-metadata.bats — verify OCI image labels and build-arg wiring.
#
# Validates via static Dockerfile analysis (no image build required):
#   - ARG VERSION, ARG GIT_COMMIT, ARG BUILD_DATE are declared
#   - All required org.opencontainers.image.* LABEL keys are present
#   - version/revision/created labels reference the correct ARG variables
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    DOCKERFILE="${REPO_ROOT}/Dockerfile"
}

@test "Dockerfile declares ARG VERSION" {
    run grep -E '^ARG VERSION=' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile declares ARG GIT_COMMIT" {
    run grep -E '^ARG GIT_COMMIT=' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile declares ARG BUILD_DATE" {
    run grep -E '^ARG BUILD_DATE=' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.title" {
    run grep -F 'org.opencontainers.image.title' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.description" {
    run grep -F 'org.opencontainers.image.description' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.url" {
    run grep -F 'org.opencontainers.image.url' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.source" {
    run grep -F 'org.opencontainers.image.source' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.vendor" {
    run grep -F 'org.opencontainers.image.vendor' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.licenses" {
    run grep -F 'org.opencontainers.image.licenses' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has LABEL org.opencontainers.image.authors" {
    run grep -F 'org.opencontainers.image.authors' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "org.opencontainers.image.version is wired to VERSION build-arg" {
    run grep -F 'org.opencontainers.image.version="${VERSION}"' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "org.opencontainers.image.revision is wired to GIT_COMMIT build-arg" {
    run grep -F 'org.opencontainers.image.revision="${GIT_COMMIT}"' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "org.opencontainers.image.created is wired to BUILD_DATE build-arg" {
    run grep -F 'org.opencontainers.image.created="${BUILD_DATE}"' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}

@test "Dockerfile has USER directive (non-root)" {
    run grep -E '^USER ' "${DOCKERFILE}"
    [ "$status" -eq 0 ]
}
