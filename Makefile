# Convenience wrappers. Everything here is a one-liner you can also type by hand.
.PHONY: help setup build test docs memo docker docker-build clean

PY ?= python3
VENV := .venv
BIN := $(VENV)/bin

help:                       ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}'

setup:                      ## create .venv and install dependencies
	$(PY) -m venv $(VENV)
	$(BIN)/pip install --upgrade pip
	$(BIN)/pip install -r requirements.txt

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
