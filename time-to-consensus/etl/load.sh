#! /usr/bin/env bash

CSV_FILE=${1:-./.raw/output.csv}

psql $POSTGRES_CONNECTION_STRING -c "\copy ecosystem.metric(name, period, timestamp_range, total) FROM '$CSV_FILE' WITH (FORMAT csv, HEADER true);"