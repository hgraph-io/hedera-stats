#! /usr/bin/env bash

# Get the latest timestamp from the database
LATEST_END_NS=$(psql $POSTGRES_CONNECTION_STRING -t -A -c "select coalesce(max(upper(timestamp_range)), '0')::bigint from ecosystem.metric where name = 'avg_time_to_consensus';")

LATEST_END_SEC=$((LATEST_END_NS / 1000000000))

if [ "$LATEST_END_SEC" -eq 0 ]; then
  echo "Error: previous data not found, run ./time-to-consensus/run.sh first" >&2
  exit 1
else
  # Take the END of the last interval as the start of the next query
  START_TIME=$(date -r "$LATEST_END_SEC" -u +"%Y-%m-%dT%H:00:00Z")
fi

END_TIME=$(date -u +"%Y-%m-%dT%H:00:00Z")

if [[ "$START_TIME" < "$END_TIME" ]]; then
  promtool query range \
    --format=json \
    --step=1h \
    --start="$START_TIME" \
    --end="$END_TIME" \
    $PROMETHEUS_ENDPOINT \
    'avg(platform_secC2RC{environment="mainnet"})'
else
  echo "No new data to fetch (START_TIME >= END_TIME)"
fi