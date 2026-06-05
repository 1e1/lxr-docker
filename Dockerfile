# LXR image: Perl CGI + nginx + fcgiwrap + Universal Ctags + PostgreSQL client
# + full-text search. swish-e is the active engine; glimpse is built best-effort
# (it is not packaged in Debian) and is switchable in config/lxr.conf.
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        perl \
        libdbi-perl \
        libdbd-pg-perl \
        libfile-mmagic-perl \
        universal-ctags \
        postgresql-client \
        swish-e \
        nginx-light \
        fcgiwrap \
        spawn-fcgi \
        wget \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Note: glimpse is intentionally NOT installed. Debian removed it (license) and
# its source tarball is no longer available in the archive, so it cannot be
# built reliably. swish-e (installed above) is the free-text search engine.

# LXR sources (downloaded by `make install` into ./lxr)
COPY lxr/ /opt/lxr/

# Pre-generated static configuration (no wizard at runtime)
COPY config/lxr.conf       /opt/lxr/lxr.conf
COPY config/initdb.sql     /opt/lxr/initdb.sql
COPY config/db-scripts.d/  /opt/lxr/custom.d/db-scripts.d/
COPY config/nginx-lxr.conf /etc/nginx/conf.d/lxr.conf
COPY docker/entrypoint.sh  /entrypoint.sh

RUN chmod +x /entrypoint.sh \
        /opt/lxr/genxref /opt/lxr/source /opt/lxr/ident \
        /opt/lxr/diff /opt/lxr/search /opt/lxr/showconfig /opt/lxr/perf \
        /opt/lxr/custom.d/db-scripts.d/*.sh \
    && rm -f /etc/nginx/sites-enabled/default \
    && install -d -o www-data -g www-data /var/lib/lxr \
    && install -d /var/run

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
