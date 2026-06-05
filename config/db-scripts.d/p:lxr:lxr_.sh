#!/bin/sh
# Re-create the LXR tables. genxref's purgeall() runs this during a full
# reindex (--reindexall): it disconnects, runs this script, then reconnects.
#
# The database and role are owned by the postgres container, so we ONLY rebuild
# tables here (no dropdb/createdb/createuser). That is what the old project got
# wrong; keeping it table-only avoids the NO_DB / counter-table workarounds.
#
# genxref derives this filename from lxr.conf: engine "p", dbname "lxr",
# prefix "lxr_"  ->  p:lxr:lxr_.sh
export PGPASSWORD="${LXR_DB_PASSWORD:-lxr}"
exec psql -h "${LXR_DB_HOST:-db}" -p "${LXR_DB_PORT:-5432}" \
          -U "${LXR_DB_USER:-lxr}" -d "${LXR_DB_NAME:-lxr}" \
          -v ON_ERROR_STOP=1 -q -f /opt/lxr/initdb.sql
