#! /usr/bin/env bash

# CSV header
echo '"name","period","timestamp_range","total"'

FILTER=$(cat <<END
.[0].values[] | [
  # convert to value used for timestamp_range
  (.[0] | floor | tostring + "000000000"),
  # add an hour
  ((.[0] + 3600) | floor | tostring + "000000000"),
  (.[1] | tonumber * 1000000000 | floor)
] | [
  (
    "[" + .[0] + ", " + .[1] + ")"
  ),
  # Convert seconds to nanoseconds
  .[2]
] | [
  "avg_time_to_consensus",
  "hour",
  .[0],
  .[1]
] | @csv
END
)

jq --raw-output "$FILTER"
