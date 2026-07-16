#!/bin/bash
# =====================================================
# Hedera Stats - Migration Runner
# =====================================================
# Applies migrations/NNN-name.sql in filename order, exactly once each, tracked
# in ecosystem.schema_migrations. Idempotent: already-applied versions are
# skipped, so it is safe to re-run any time.
#
# This is the CMD of the one-shot runner image (docker/migrate/Dockerfile). Run
# it against a network's database via docker-compose:
#
#   docker compose run --rm mainnet
#   docker compose run --rm testnet
#
# Connection is over the Unix socket (PGHOST defaults to /var/run/postgresql),
# credential-free via peer auth (the container runs as the host postgres UID).
# Compose sets PGPORT/PGDATABASE and PGOPTIONS (role) per network. Override the
# PG* vars to point elsewhere (e.g. a TCP host with PGPASSWORD for ad-hoc runs).
#
# These migrations are pure schema SQL. Extensions (timestamp9, http) and the
# logical replication subscription are external prerequisites provisioned by a
# superuser before this runs.
# =====================================================

set -euo pipefail

# libpq connection settings. Socket + trust auth = credential-free in the
# container; every psql call below inherits these, so none pass -h/-U/-d.
export PGHOST="${PGHOST:-/var/run/postgresql}"
export PGPORT="${PGPORT:-5432}"
export PGDATABASE="${PGDATABASE:-${POSTGRES_DB:-hedera_stats}}"
export PGUSER="${PGUSER:-${POSTGRES_USER:-postgres}}"

# Readonly role that consumer/API roles inherit from — granted access to the
# ecosystem objects (see the grants migration). Defaults to <db>_readonly
# (e.g. hedera_mainnet_readonly); override with READONLY_ROLE if it differs.
READONLY_ROLE="${READONLY_ROLE:-${PGDATABASE}_readonly}"

# -v readonly_role=... exposes it to migrations as :"readonly_role". Harmless
# for migrations that don't reference it.
PSQL="psql -v ON_ERROR_STOP=1 -v readonly_role=${READONLY_ROLE}"
MIG_DIR="${1:-/sql/migrations}"

# Tracking table. Defaults to ecosystem.schema_migrations; a separate migration
# set (e.g. the public-schema matviews, applied as a different owner role) sets
# SCHEMA_MIGRATIONS_TABLE=public.schema_migrations so it tracks independently.
MIG_TABLE="${SCHEMA_MIGRATIONS_TABLE:-ecosystem.schema_migrations}"
MIG_SCHEMA="${MIG_TABLE%%.*}"

# Ensure the tracking schema + table exist before anything is applied.
$PSQL <<SQL
CREATE SCHEMA IF NOT EXISTS ${MIG_SCHEMA};
CREATE TABLE IF NOT EXISTS ${MIG_TABLE} (
    version    text PRIMARY KEY,
    filename   text NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now()
);
SQL

applied="$($PSQL -tAc "SELECT version FROM ${MIG_TABLE}")"

shopt -s nullglob
count_applied=0
count_skipped=0
for f in "$MIG_DIR"/[0-9][0-9][0-9]-*.sql; do
  base="$(basename "$f")"
  version="${base%%-*}"

  if grep -qxF "$version" <<<"$applied"; then
    echo "[migrate]   skip  $base (already applied)"
    count_skipped=$((count_skipped + 1))
    continue
  fi

  echo "[migrate]   apply $base"
  # Swap public.interval_granularity (mirror-node-only enum) for text. The
  # baseline migrations are already pre-swapped; this covers hand-written ones.
  sed 's/public\.interval_granularity/text/g' "$f" | $PSQL

  # Record only after the migration succeeds (ON_ERROR_STOP aborts above on
  # failure, so an unrecorded migration is retried next run).
  # ponytail: run-then-record is non-atomic — a migration that
  # half-applies then errors leaves partial state. Wrap the file body in
  # BEGIN/COMMIT inside the .sql itself if a migration needs all-or-nothing.
  $PSQL -c "INSERT INTO ${MIG_TABLE} (version, filename) VALUES ('${version}', '${base}')"
  count_applied=$((count_applied + 1))
done

echo "[migrate] Done. Applied ${count_applied}, skipped ${count_skipped}."
