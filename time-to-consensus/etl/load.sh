#! /usr/bin/env bash

# echo "not implemented yet"
# TODO: is the timestampe range off by an hour?
psql $POSTGRES_CONNECTION_STRING -c "\copy ecosystem.metric(name, period, timestamp_range, total) FROM './.raw/output.csv' WITH (FORMAT csv, HEADER true);"
