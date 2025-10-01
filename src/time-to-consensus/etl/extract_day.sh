#!/usr/bin/env bash
set -eo pipefail

# Add logging function
log() {
  echo "$(date -u '+%Y-%m-%d %H:%M:%S') [extract_day] $1" >&2
}

log "Starting daily extraction"

# Latest upper bound in nanoseconds for the daily series
LATEST_END_NS=$(psql "$POSTGRES_CONNECTION_STRING" -t -A -c \
  "select coalesce(max(upper(timestamp_range)), '0')::bigint
     from ecosystem.metric
    where name = 'avg_time_to_consensus'
      and period = 'day';")

log "Latest timestamp from DB: $LATEST_END_NS"

LATEST_END_SEC=$((LATEST_END_NS / 1000000000))

# When empty, backfill by year to stay within Prometheus range limits
if [ "$LATEST_END_SEC" -eq 0 ]; then
  log "Database empty, starting backfill from 2023"
  for i in {2023..2025}; do
    log "Fetching year $i data"
    promtool query range \
      --format=json \
      --step=1d \
      --start="$i-01-01T00:00:00Z" \
      --end="$i-12-31T23:59:59Z" \
      "$PROMETHEUS_ENDPOINT" \
      'avg(platform_secC2RC{environment="mainnet"})'
  done
else
  # Continue from the end of the last interval, aligned to 00:00:00Z
  START_TIME=$(date --date="@$LATEST_END_SEC" -u +"%Y-%m-%dT00:00:00Z")
  log "Continuing from: $START_TIME"
fi

END_TIME=$(date -u +"%Y-%m-%dT00:00:00Z")
log "Querying up to: $END_TIME"

if [[ -n "$START_TIME" && "$START_TIME" < "$END_TIME" ]]; then
  log "Fetching range: $START_TIME to $END_TIME"
  promtool query range \
    --format=json \
    --step=1d \
    --start="$START_TIME" \
    --end="$END_TIME" \
    "$PROMETHEUS_ENDPOINT" \
    'avg(platform_secC2RC{environment="mainnet"})'
else
  log "No new data to fetch (START_TIME: ${START_TIME:-empty}, END_TIME: $END_TIME)"
fi

log "Extraction complete"