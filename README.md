# LXR in Docker

Browse a source tree in the [LXR](https://codeberg.org/ajlittoz/CB_LXRsource/)
cross-reference web interface, with everything running in Docker — no tools to
install on the host and no manual configuration step.

- Indexer and browser: **LXR** (the latest upstream release)
- Cross-reference storage: **PostgreSQL**
- Full-text search: **swish-e**
- Web layer: **nginx + fcgiwrap**, configuration baked into the image

## Requirements

- Docker and Docker Compose v2 (`docker compose version`)
- Internet access once, to download the LXR sources (`make install`)

## Quick start

```bash
git clone https://github.com/1e1/lxr-docker.git
cd lxr-docker
make install                        # download the latest LXR release (once)
cp -r /path/to/your/code/* ./src/   # the code you want to browse
make up                             # build, start (db + lxr), and index
```

Then open <http://localhost:8080/lxr/source>.

The first `make up` indexes the tree (follow it with `make logs`); later starts
reuse the saved index.

> To browse code already on disk without copying it, set its path in `.env`
> (`LXR_SOURCE_DIR=/absolute/path/to/code`) and run `make up`. The directory is
> mounted read-only.

## Commands

| Command | Description |
| --- | --- |
| `make up` | Build and start (indexes on first run) |
| `make reindex` | Re-index after the sources change |
| `make logs` | Follow the lxr container logs |
| `make export` | Write a static HTML copy into `./out` |
| `make down` | Stop the containers (keeps the index) |
| `make clean` | Stop and delete the database + index (sources untouched) |

Settings live in `.env` (copy from `.env.example`): `LXR_WEB_PORT`,
`LXR_SOURCE_DIR`, `LXR_EXPORT_DIR`, and the `LXR_DB_*` credentials.

## How it works

The configuration is static and committed; nothing is generated or patched at
runtime.

```
Dockerfile             image: Perl, nginx, fcgiwrap, Universal Ctags, PostgreSQL client, swish-e
docker/entrypoint.sh   wait for PostgreSQL, create the schema, index on first run, then serve
config/lxr.conf        LXR configuration: single tree, virtual root /lxr, PostgreSQL, swish-e
config/initdb.sql      PostgreSQL schema (tables, counters, functions, triggers)
config/db-scripts.d/   table (re)creation used by a full reindex
config/nginx-lxr.conf  nginx location block for the LXR scripts and assets
docker-compose.yml     services: db (PostgreSQL) and lxr (plus an export profile)
```

Notes:

- Cross-reference data (definitions, usages) lives in **PostgreSQL**; the
  free-text search box is powered by **swish-e**.
- The database and role are created by the `postgres` container, so the schema
  setup only ever creates tables — no `dropdb`/`createdb` at index time.
- glimpse is **not** installed: Debian removed it and its source tarball is no
  longer available. swish-e covers full-text search; to use glimpse instead,
  provide the binary and point `glimpsebin` at it in `config/lxr.conf`.
- The web server is configured so the UI works behind any host, port or reverse
  proxy: links are emitted relative to wherever it is reached.
- The files in `config/` were produced once with LXR's `configure-lxr.pl`
  wizard, then frozen. See [config/REGENERATE.md](config/REGENERATE.md) to
  regenerate them.

## License

Distributed under the terms in [LICENSE](LICENSE).
