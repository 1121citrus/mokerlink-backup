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

ARG HA_BASH_BASE_TAG=1.0.0
FROM 1121citrus/ha-bash-base:${HA_BASH_BASE_TAG}

# Download pfmotion_wget.sh and convert it to using environment variables and
# docker secrets
RUN set -Eeux; \
    apk update && \
    apk add --no-cache --no-interactive --upgrade \
        aws-cli>2.27 \
        bzip2>1.0 \
        bzip3>1.5 \
        expect>5.45 \
        gnupg>2.4 \
        gzip>1.14 \
        openssh>10.0 \
        openssl>3.5 \
        pigz>2.8 \
        pixz>1.0 \
        sshpass>1.10 \
        xz>5.8 \
        zip>3.0 \
        && \
    mkdir -pv -m 700 /root/.gnupg && \
    mkdir -pv -m 700 /root/.ssh && \
    touch /root/.gnupg/pubring.kbx && \
    chmod 600 /root/.gnupg/pubring.kbx && \
    true

COPY --chmod=755 ./src/bin/* /usr/local/bin

HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD /usr/local/bin/healthcheck

CMD [ "/usr/local/bin/startup" ]

