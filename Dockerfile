# syntax=docker/dockerfile:1

# An application specific service to create Mokerlink managed
# network switch backups and copy them off site.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

# aws-backup-base 1.2.3 (AL2023 2023.12.20261102, supercronic v0.2.49 built
# with Go 1.27.4, python3-pygments excluded), pinned by multi-arch index
# digest so builds are reproducible rather than tracking whatever `:latest`
# points at.
ARG BASE_IMAGE=1121citrus/aws-backup-base@sha256:dc4c176e47b9d1b818c149466bcb61ed2e5ea643a0d947d6b8fc8519b2b14852
ARG VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown
ARG UID=10001

# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG VERSION
ENV VERSION=${VERSION}

ARG GIT_COMMIT
ENV GIT_COMMIT=${GIT_COMMIT}

ARG BUILD_DATE
ENV BUILD_DATE=${BUILD_DATE}

ARG UID

# OCI image annotations (https://github.com/opencontainers/image-spec/blob/main/annotations.md)
LABEL org.opencontainers.image.title="mokerlink-backup" \
      org.opencontainers.image.description="Download configuration backups from a Mokerlink managed network switch" \
      org.opencontainers.image.url="https://github.com/1121citrus/mokerlink-backup" \
      org.opencontainers.image.source="https://github.com/1121citrus/mokerlink-backup" \
      org.opencontainers.image.vendor="1121 Citrus Avenue" \
      org.opencontainers.image.authors="James Hanlon <jim@hanlonsoftware.com>" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# Install required utilities and configure environment.
# bzip3 and pixz are not available in AL2023; gzip, bzip2, xz, lzop, and pigz
# cover all common backup compression scenarios.
# AL2023 locks dnf to the base image's release version, so a plain
# `dnf upgrade` cannot reach security fixes published after the base image
# was built.  `--releasever=latest` resolves against the newest AL2023
# repository snapshot so every installed package picks up current fixes.
# Install newer IDNA and setuptools alongside their RPMs without removing
# the system-managed files.
# hadolint ignore=DL3013,DL3041
RUN set -eux; \
    dnf install -y --quiet --releasever=latest \
        bzip2 \
        expect \
        gnupg2 \
        gzip \
        lzop \
        openssh-clients \
        openssl \
        pigz \
        python3 \
        python3-pip \
        xz \
        zip \
    && pip3 install --no-cache-dir --upgrade \
        'cryptography>=50.0.2' \
        'jaraco.context>=6.1.0' \
        'tftpy>=0.8.0' \
        'urllib3>=2.6.3' \
        'wheel>=0.46.2' \
        'zipp>=3.23.1' \
    && pip3 install --no-cache-dir --upgrade --ignore-installed \
        'idna>=3.20' \
        'setuptools>=82.0.1' \
    && dnf upgrade -y --quiet --releasever=latest \
    && dnf reinstall -y --quiet --releasever=latest python3-urllib3 \
    && dnf remove -y --quiet --releasever=latest python3-pip \
    && useradd \
        --create-home --shell /sbin/nologin \
        --uid "${UID}" mokerlink-backup \
    && install -d -m 0700 -o mokerlink-backup \
        /home/mokerlink-backup/.gnupg \
        /home/mokerlink-backup/.ssh \
    && install -m 0600 -o mokerlink-backup /dev/null \
        /home/mokerlink-backup/.gnupg/pubring.kbx \
    && install -d -m 755 /var/spool/cron \
    && install -d -m 0755 -o mokerlink-backup /var/spool/cron/crontabs \
    && mkdir -pv /usr/local/include/bash \
    && ln -sf /usr/local/bin/common-functions /usr/local/include/bash/common-functions \
    && mkdir -p /usr/local/share/mokerlink-backup \
    && printf '%s\n' "${VERSION}" > /usr/local/share/mokerlink-backup/version \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY --chmod=755 ./src/bin/* /usr/local/bin
COPY --chmod=755 ./src/common-functions /usr/local/bin/

USER mokerlink-backup

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 CMD /usr/local/bin/healthcheck

CMD [ "/usr/local/bin/startup" ]
