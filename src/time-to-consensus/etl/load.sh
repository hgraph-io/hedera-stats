#! /usr/bin/env bash

LOAD_DIR="$(dirname "$(realpath "$0")")"

psql $POSTGRES_CONNECTION_STRING -c "$(cat $LOAD_DIR/load.sql)"
