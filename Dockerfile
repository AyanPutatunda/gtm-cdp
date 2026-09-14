# ─────────────────────────────────────────────────────────────────────────────
# A one-command way to run this project without installing anything but Docker.
#
#   docker build -t gtm-cdp .
#   docker run --rm -v "$PWD:/app" gtm-cdp
#
# The default target is DuckDB, so there is no warehouse to connect to and no
# credentials to supply. The bind mount is what puts gtm_cdp.duckdb, target/
# and logs/ back on your machine after the run; drop it and the container is
# a throwaway that just proves the build is green.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim

# dbt does not support 3.14 yet, which is why this pins 3.12 rather than
# tracking latest. Nothing else here is version-sensitive.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DBT_PROFILES_DIR=/app

WORKDIR /app

# Dependencies first, so editing a model does not reinstall dbt.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# seeds -> models -> tests, interleaved in DAG order.
# Expect: PASS=223 WARN=4 ERROR=0 SKIP=0 TOTAL=227
CMD ["dbt", "build"]
