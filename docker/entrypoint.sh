#!/bin/sh
# LXR container entrypoint:
#   1. wait for PostgreSQL,
#   2. create the schema on first run,
#   3. index /src/v1 if the database is empty (or LXR_REINDEX=1),
#   4. serve the UI with nginx + fcgiwrap.
set -eu

LXR_HOME=/opt/lxr
URL="${LXR_URL:-http://localhost/lxr}"
export PGHOST="${LXR_DB_HOST:-db}"
export PGPORT="${LXR_DB_PORT:-5432}"
export PGDATABASE="${LXR_DB_NAME:-lxr}"
export PGUSER="${LXR_DB_USER:-lxr}"
export PGPASSWORD="${LXR_DB_PASSWORD:-lxr}"

cd "$LXR_HOME"
# Full-text search index dir (swish-e). www-data must be able to write it.
install -d -o www-data -g www-data /var/lib/lxr /var/lib/lxr/swish

# 1) Wait for PostgreSQL.
echo "[lxr] Waiting for PostgreSQL at $PGHOST:$PGPORT ..."
i=0
until pg_isready -q; do
    i=$((i + 1))
    [ "$i" -gt 60 ] && { echo "[lxr] PostgreSQL unreachable after 60s"; exit 1; }
    sleep 1
done

# 2) Create the schema if the tables are missing (DB + role come from the
#    postgres container; we only create tables -> no NO_DB workarounds).
have=$(psql -tAc "SELECT to_regclass('public.lxr_files') IS NOT NULL" 2>/dev/null || echo f)
if [ "$have" != "t" ]; then
    echo "[lxr] Creating LXR schema ..."
    psql -v ON_ERROR_STOP=1 -q -f "$LXR_HOME/initdb.sql"
fi

# 3) Index when the DB is empty, or on explicit request.
indexed=$(psql -tAc "SELECT count(*) FROM lxr_files" 2>/dev/null || echo 0)
if [ "${LXR_REINDEX:-0}" = "1" ] || [ "$indexed" -eq 0 ]; then
    if [ -n "$(ls -A /src/v1 2>/dev/null || true)" ]; then
        echo "[lxr] Indexing /src/v1 — this can take a while on large trees ..."
        if ./genxref --url="$URL" --allversions --reindexall --novacuum; then
            echo "[lxr] Indexing complete."
        else
            echo "[lxr] WARNING: genxref reported errors; the UI will still start."
        fi
        chown -R www-data:www-data /var/lib/lxr
    else
        echo "[lxr] /src/v1 is empty — put your code there, then: make reindex"
    fi
fi

# 4) Serve.
rm -f /var/run/fcgiwrap.socket
spawn-fcgi -s /var/run/fcgiwrap.socket -u www-data -g www-data -M 0660 /usr/sbin/fcgiwrap
echo "[lxr] Ready. Open the UI at  http://localhost:<mapped-port>/lxr/source"
exec nginx -g 'daemon off;'
