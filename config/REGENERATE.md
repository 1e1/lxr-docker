# How `config/` was generated

`config/lxr.conf`, `config/initdb.sql` and `config/db-scripts.d/` are the frozen
output of LXR's own `configure-lxr.pl` wizard, so no wizard runs at build or
start time. You only need this if you change the deployment shape (different
virtual root, multiple versions, another database, ...).

`config/nginx-lxr.conf` is hand-written (the wizard's nginx output has a
nested-location capture bug that sends a wrong `SCRIPT_NAME`, and it bakes an
absolute base URL); keep the hand-written one.

## 1. Run the wizard against the downloaded sources

`configure-lxr.pl` probes `$PATH` for `swish-e`; provide a stub so it configures
the search engine even when swish-e is not installed locally:

```bash
cd lxr
mkdir -p /tmp/fakebin && printf '#!/bin/sh\n' > /tmp/fakebin/swish-e && chmod +x /tmp/fakebin/swish-e
mkdir -p /tmp/gen
printf '%s\n' s n s '' '' '' p /var/lib/lxr/swish '' LXR n f /src '' '' l v1 '' '' '' '' lxr '' lxr '' \
  | PATH=/tmp/fakebin:$PATH perl scripts/configure-lxr.pl --conf-dir=/tmp/gen -vv
cd ..
```

Answer key (one per line above): single tree / no more trees / shared server /
host `//localhost` (default) / no alias / section `/lxr` (default) /
DB engine **postgres** / swish-e dir `/var/lib/lxr/swish` / buttons-and-menus
(default) / caption `LXR` / no special encoding / storage **files** / source
`/src` / path root `$v` (default) / version label (default) / enumeration
**list** / version `v1` / stop / default first (default) / no ignored dir /
no include dir / DB name `lxr` / DB user `lxr` (default) / DB password `lxr` /
table prefix `lxr_` (default).

## 2. Turn the wizard output into the committed files

```bash
# lxr.conf: in-container paths, the compose DB host, drop macro comments
sed -e "s#$(pwd)/lxr#/opt/lxr#g" \
    -e 's#/tmp/fakebin/swish-e#/usr/bin/swish-e#g' \
    -e 's#dbname=lxr;host=localhost#dbname=lxr;host=db;port=5432#' \
    -e '/^#@/d' \
    /tmp/gen/lxr.conf > config/lxr.conf

# initdb.sql: the table-creation SQL only (no dropdb/createdb), un-escaping $$
python3 - <<'PY'
import re
src = open('/tmp/gen/db-scripts.d/p:lxr:lxr_.sh').read()
blocks = re.findall(r'<<END_OF_SQL\n(.*?)\nEND_OF_SQL', src, re.S)
sql = "\n".join(b for b in blocks if 'create table' in b).replace('\\$\\$', '$$')
open('config/initdb.sql','w').write(sql.strip() + "\n")
PY
```

`config/db-scripts.d/p:lxr:lxr_.sh` is a small hand-written wrapper that runs
`initdb.sql` with `psql` (genxref invokes it during `--reindexall`).
