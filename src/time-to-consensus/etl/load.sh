#! /usr/bin/env bash

CSV_FILE=${1:-./.raw/output.csv}

psql $POSTGRES_CONNECTION_STRING -f ./load.sql -v csv=$CSV_FILE
