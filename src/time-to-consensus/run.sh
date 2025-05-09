#! /usr/bin/env bash

# get environment variables from .env file
set -o allexport && source .env && set +o allexport

# check if environment variables exist
VARIABLES=("PROMETHEUS_ENDPOINT" "POSTGRES_CONNECTION_STRING")
for VAR in "${VARIABLES[@]}"; do
    if [ -z "${!VAR+x}" ]; then
        echo "Environment variable $VAR does not exist."
        exit 1
    fi
done

# List of commands to check
COMMANDS=("psql" "jq")

# Loop through the commands and check if they are available
for CMD in "${COMMANDS[@]}"; do
    if ! command -v "$CMD" &> /dev/null; then
        echo "Error: Command '$CMD' is not available in the PATH." >&2
        exit 1
    fi
done

DIR="$(dirname "$(realpath "$0")")"
echo $DIR

$DIR/etl/extract.sh | tee $DIR/.raw/data.json | $DIR/etl/transform.sh | tee $DIR/.raw/output.csv \
  | $DIR/etl/load.sh
