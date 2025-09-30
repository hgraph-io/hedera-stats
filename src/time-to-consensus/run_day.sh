#!/usr/bin/env bash
set -eo pipefail

# Load env and check deps (mirrors run.sh)
set -o allexport && source .env && set +o allexport

for VAR in PROMETHEUS_ENDPOINT POSTGRES_CONNECTION_STRING; do
  if [ -z "${!VAR+x}" ]; then
    echo "Missing $VAR"; exit 1
  fi
done

for CMD in psql jq; do
  command -v "$CMD" >/dev/null || { echo "Missing $CMD"; exit 1; }
done

DIR="$(dirname "$(realpath "$0")")"
"$DIR/etl/extract_day.sh" | tee "$DIR/.raw/data_day.json" | \
"$DIR/etl/transform_day.sh" | tee "$DIR/.raw/output_day.csv" | \
"$DIR/etl/load.sh"