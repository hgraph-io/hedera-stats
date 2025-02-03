#! /usr/bin/env bash

# get environment variables from .env file
set -o allexport && source .env && set +o allexport

# check if environment variables exist
VARIABLES=("PROMETHEUS_ENDPOINT")
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

./etl/extract_incremental.sh | tee .raw/data_incremental.json | ./etl/transform.sh | tee .raw/output_incremental.csv && ./etl/load.sh ./.raw/output_incremental.csv