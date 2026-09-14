# Convenience wrappers. Everything here is a one-liner you can also type by hand.
.PHONY: help setup build test docs memo docker docker-build clean

# First interpreter on PATH that satisfies the dependencies' requires-python
# (>= 3.10). Override with:  make setup PY=/path/to/python3.12
PY ?= $(shell for p in python3 python3.13 python3.12 python3.11 python3.10; do \
        command -v $$p >/dev/null 2>&1 && \
        $$p -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null && \
        { echo $$p; break; }; done)
VENV := .venv
BIN := $(VENV)/bin

help:                       ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}'

setup:                      ## create .venv and install dependencies
	@test -n "$(PY)" && $(PY) -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null || { \
	  echo "Need Python 3.10 or newer: dbt-core and dbt-duckdb both declare"; \
	  echo "requires-python >= 3.10. Install one, or point make at it:"; \
	  echo "    make setup PY=/usr/local/bin/python3.12"; \
	  exit 1; }
	@echo "Using $(PY) ($$($(PY) --version 2>&1))"
	$(PY) -m venv $(VENV)
	$(BIN)/pip install --quiet --upgrade pip
	$(BIN)/pip install --quiet -r requirements.txt
	@echo "Ready. Next: make build"

build:                      ## seeds -> models -> tests (expect PASS=223 WARN=4 ERROR=0)
	DBT_PROFILES_DIR=. $(BIN)/dbt build

test:                       ## tests only, against whatever is already built
	DBT_PROFILES_DIR=. $(BIN)/dbt test

docs:                       ## rebuild, then regenerate the design doc from the manifest + warehouse
	DBT_PROFILES_DIR=. $(BIN)/dbt build
	$(BIN)/python docs/build_lineage.py
	$(BIN)/python docs/build_report_data.py

memo:                       ## render MEMO.md to MEMO.pdf (needs Chrome installed)
	$(BIN)/python docs/build_memo_pdf.py

docker-build:               ## build the image
	docker build -t gtm-cdp .

docker: docker-build        ## build and run dbt inside Docker, results mounted back
	docker run --rm -v "$$PWD:/app" gtm-cdp

clean:                      ## remove build artefacts (keeps .venv)
	rm -rf target logs gtm_cdp.duckdb gtm_cdp.duckdb.wal .user.yml
