#!/usr/bin/env bash
set -eo pipefail

# Add logging function
log() {
  echo "$(date -u '+%Y-%m-%d %H:%M:%S') [run_day] $1" >&2
}

log "Starting daily ETL pipeline"

# Load env and check deps (mirrors run.sh)
set -o allexport && source .env && set +o allexport

log "Environment loaded"

for VAR in PROMETHEUS_ENDPOINT POSTGRES_CONNECTION_STRING; do
  if [ -z "${!VAR+x}" ]; then
    log "ERROR: Missing environment variable $VAR"
    exit 1
  fi
done

log "Environment variables validated"

for CMD in psql jq; do
  if ! command -v "$CMD" >/dev/null; then
    log "ERROR: Missing command $CMD"
    exit 1
  fi
done

log "Dependencies validated"

DIR="$(dirname "$(realpath "$0")")"
log "Starting ETL pipeline: extract -> transform -> load"

"$DIR/etl/extract_day.sh" | tee "$DIR/.raw/data_day.json" | \
"$DIR/etl/transform_day.sh" | tee "$DIR/.raw/output_day.csv" | \
"$DIR/etl/load.sh"

log "Daily ETL pipeline completed successfully"