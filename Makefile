# LXR in Docker — minimal commands.
#
# Quick start:
#   1. make install            # once, needs Internet (downloads LXR sources)
#   2. put the code to browse into ./src   (or set LXR_SOURCE_DIR)
#   3. make up                 # builds, starts (db + lxr), and indexes
#   then open  http://localhost:8080/lxr/source

-include .env

LXR_WEB_PORT   ?= 8080
LXR_SOURCE_DIR ?= ./src
LXR_EXPORT_DIR ?= ./out
LXR_GIT_REPO   ?= https://codeberg.org/ajlittoz/CB_LXRsource.git
export LXR_WEB_PORT LXR_SOURCE_DIR LXR_EXPORT_DIR

.PHONY: help install up reindex logs export down clean

help:
	@echo "LXR in Docker:"
	@echo "  make install   Download the latest LXR release into ./lxr (once, needs Internet)"
	@echo "  make up         Build + start (db + lxr); first start indexes ./src"
	@echo "  make reindex    Re-index after the sources change"
	@echo "  make logs       Follow the lxr container logs"
	@echo "  make export     Write a static HTML copy into $(LXR_EXPORT_DIR)"
	@echo "  make down       Stop the containers (keeps the index)"
	@echo "  make clean      Stop and DELETE the database + index (sources untouched)"
	@echo ""
	@echo "  UI: http://localhost:$(LXR_WEB_PORT)/lxr/source"

install:
	@if [ -d lxr ]; then \
	    echo "lxr/ already present (remove it to re-download)."; \
	else \
	    tag=$$(git ls-remote --tags --refs $(LXR_GIT_REPO) 'release-*' \
	          | awk -F/ '{print $$NF}' | sort -V | tail -1); \
	    test -n "$$tag" || { echo "Could not determine the latest LXR release tag." >&2; exit 1; }; \
	    echo "Latest LXR release: $$tag"; \
	    git clone --depth 1 --branch "$$tag" $(LXR_GIT_REPO) lxr; \
	fi

up:
	@test -d lxr || { echo "Run 'make install' first."; exit 1; }
	@mkdir -p "$(LXR_SOURCE_DIR)" "$(LXR_EXPORT_DIR)"
	docker compose up -d --build
	@echo "→ http://localhost:$(LXR_WEB_PORT)/lxr/source  (first run indexes; see: make logs)"

reindex:
	docker compose exec lxr sh -c \
	  'cd /opt/lxr && ./genxref --url=http://localhost/lxr --allversions --reindexall --novacuum && chown -R www-data:www-data /var/lib/lxr'

logs:
	docker compose logs -f lxr

export:
	docker compose --profile export run --rm export
	@echo "Static copy in $(LXR_EXPORT_DIR)/lxr/source"

down:
	docker compose down

clean:
	docker compose down -v
