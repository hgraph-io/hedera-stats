#! /usr/bin/env bash

LOAD_DIR="$(dirname "$(realpath "$0")")"
CSV_FILE=${1:-$LOAD_DIR/../.raw/output.csv}
echo $CSV_FILE

psql $POSTGRES_CONNECTION_STRING -f $LOAD_DIR/load.sql -v csv=$CSV_FILE
