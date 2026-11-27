# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
#
# Modifié le 28/10/2026 par l'équipe du projet (AGPL v3, section 5a) : nginx 1.30.6, sans les plugins.
# Dockerfile d'origine : docker/Dockerfile du dépôt taigaio/taiga-front, copié le 23/10/2026 (après la 6.10.3).

FROM nginx:1.30.6-alpine
LABEL maintainer="support@taiga.io"

COPY docker/default.conf /etc/nginx/conf.d/default.conf
COPY docker/conf.json.template /
COPY docker/config_env_subst.sh /docker-entrypoint.d/30_config_env_subst.sh

RUN set -eux; \
    apk update; \
    apk add --no-cache --virtual .build-deps \
       subversion; \
    apk add \
       bash; \
    # Install taiga-front core
    wget https://github.com/taigaio/taiga-front-dist/archive/6.10.3.zip -O source.zip; \
    unzip source.zip; \
    mv /taiga-front-dist-6.10.3 /taiga; \
    mv /conf.json.template taiga/dist/; \
    chmod +x /docker-entrypoint.d/30_config_env_subst.sh; \
    # Remove unused dependencies
    apk del --no-cache .build-deps; \
    rm source.zip; \
    # Ready for nginx
    mv /taiga/dist/* /usr/share/nginx/html; \
    rm -rf /taiga
