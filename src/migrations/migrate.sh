#!/bin/bash
# =====================================================
# Hedera Stats - Migration Runner
# =====================================================
# Applies migrations/NNN-name.sql in filename order, exactly once each, tracked
# in ecosystem.schema_migrations. Idempotent: already-applied versions are
# skipped, so this is safe to run on every boot AND standalone against a live
# subscriber.
#
# This IS the bring-up entrypoint. On first boot it is mounted into
# /docker-entrypoint-initdb.d (see docker-compose.yml) and Postgres runs it
# automatically; 001-init.sql creates the extensions, mirror-node types and
# schema, then 002+ install the metrics. To update a LIVE subscriber without
# recreating the volume, run it directly:
#
#   docker compose exec stats-db bash /sql/migrations/migrate.sh
#
# Connection is over the Unix socket (PGHOST defaults to /var/run/postgresql),
# so no password is needed: the postgres image's pg_hba.conf trusts local
# socket connections. Override the PG* vars below to point at a different
# database (e.g. a TCP host for ad-hoc runs).
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

PSQL="psql -v ON_ERROR_STOP=1"
MIG_DIR="${1:-/sql/migrations}"

# Ensure the schema + tracking table exist before anything is applied. Both are
# idempotent; the schema is (re)created by 001-init.sql too, but the tracking
# table must exist before we can record 001 itself.
$PSQL <<'SQL'
CREATE SCHEMA IF NOT EXISTS ecosystem;
CREATE TABLE IF NOT EXISTS ecosystem.schema_migrations (
    version    text PRIMARY KEY,
    filename   text NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now()
);
SQL

applied="$($PSQL -tAc 'SELECT version FROM ecosystem.schema_migrations')"

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
  $PSQL -c "INSERT INTO ecosystem.schema_migrations (version, filename) VALUES ('${version}', '${base}')"
  count_applied=$((count_applied + 1))
done

echo "[migrate] Done. Applied ${count_applied}, skipped ${count_skipped}."
