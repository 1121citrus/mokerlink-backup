# syntax=docker/dockerfile:1

# An application specific service to create Mokerlink managed
# network switch backups and copy them off site.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

ARG ALPINE_TAG=3.21
FROM alpine:${ALPINE_TAG}

ARG VERSION=dev

# install required utilities and configure environment
# hadolint ignore=DL3018,SC2261,SC3041,DL3059
RUN set -Eeux; \
    apk update && \
    apk upgrade --no-cache --no-interactive && \
    apk add --no-cache --no-interactive --upgrade \
        'aws-cli>2.20' \
        'bash>5.2' \
        'bzip2>1.0' \
        'bzip3>1.3' \
        'expect>5.45' \
        'gnupg>2.4' \
        'gzip>1.12' \
        'lzop>1.04' \
        'openssh>9.8' \
        'openssl>3.3' \
        'pigz>2.8' \
        'pixz>1.0' \
        'xz>5.6' \
        'zip>3.0' \
        && \
    install -d -m 700 /root/.gnupg /root/.ssh && \
    touch /root/.gnupg/pubring.kbx && \
    chmod 600 /root/.gnupg/pubring.kbx && \
    mkdir -pv /usr/local/include/bash && \
    ln -sf /usr/local/bin/common-functions /usr/local/include/bash/common-functions && \
    mkdir -p /usr/local/share/mokerlink-backup && \
    printf '%s\n' "${VERSION}" > /usr/local/share/mokerlink-backup/version && \
    true

COPY --chmod=755 ./src/bin/* /usr/local/bin
COPY --chmod=755 ./src/common-functions /usr/local/bin/

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 CMD /usr/local/bin/healthcheck

CMD [ "/usr/local/bin/startup" ]

