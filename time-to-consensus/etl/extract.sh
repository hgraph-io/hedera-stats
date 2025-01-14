#! /usr/bin/env bash


for i in {2020..2025}
do
  promtool query range \
    --format=json \
    --step=1h \
    --start="$i-01-01T00:00:00Z" \
    --end="$i-12-31T23:59:59Z" \
    $PROMETHEUS_ENDPOINT \
    'avg(platform_secC2RC{environment="mainnet"})'
done
