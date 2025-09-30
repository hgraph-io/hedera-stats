#!/usr/bin/env bash
set -eo pipefail

# CSV header
echo '"name","period","timestamp_range","total"'

FILTER=$(cat <<'END'
.[0].values[] | [
  # lower bound in nanoseconds
  (.[0] | floor | tostring + "000000000"),
  # add one day (86400 seconds) for upper bound
  ((.[0] + 86400) | floor | tostring + "000000000"),
  # seconds → nanoseconds for the consensus time value
  (.[1] | tonumber * 1000000000 | floor)
] | [
  ("[" + .[0] + ", " + .[1] + ")"),
  .[2]
] | [
  "avg_time_to_consensus",
  "day",
  .[0],
  .[1]
] | @csv
END
)

jq --raw-output "$FILTER"