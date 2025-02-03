#! /usr/bin/env bash

start_time=$(date -v-1H -u +"%Y-%m-%dT%H:00:00Z")
end_time=$(date -u +"%Y-%m-%dT%H:00:00Z")

promtool query range \
  --format=json \
  --step=1h \
  --start="$start_time" \
  --end="$end_time" \
  $PROMETHEUS_ENDPOINT \
  'avg(platform_secC2RC{environment="mainnet"})'
