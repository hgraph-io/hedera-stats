#!/bin/bash
# =====================================================
# Hedera Stats - Database Initialization
# =====================================================
# Runs once when the Postgres container starts for the first time:
#   1. Creates extensions (timestamp9, http)
#   2. Creates mirror-node enum/domain types (00-mirror-node-types.sql)
#   3. Applies migrations/NNN-*.sql via migrate.sh — the schema (001) and every
#      metric / schema object, tracked so each runs exactly once
#
# Every metric and schema object is a migration. To add or change one, add a new
# src/migrations/NNN-name.sql; apply it to a live subscriber without recreating
# the volume via:
#   docker compose exec stats-db bash /sql/migrations/migrate.sh
#
# This container is a Postgres logical replication SUBSCRIBER. Mirror-node tables
# arrive via a subscription to the mirror node (publisher); FDW is no longer used.
#
# pg_cron scheduling (src/jobs/pg_cron_metrics.sql) is intentionally NOT set up
# here — it drives metric loading and belongs on the publisher, not a subscriber.
# =====================================================

set -e

DB="${POSTGRES_DB:-hedera_stats}"
PSQL="psql -v ON_ERROR_STOP=1 --username $POSTGRES_USER --dbname $DB"

echo "[init] Running mirror node type definitions in $DB..."
$PSQL -f /docker-entrypoint-initdb.d/00-mirror-node-types.sql

echo "[init] Creating extensions in $DB..."
$PSQL <<SQL
CREATE EXTENSION IF NOT EXISTS timestamp9;
CREATE EXTENSION IF NOT EXISTS http;
SQL

echo "[init] Applying migrations from /sql/migrations/..."
# The runner applies each NNN-*.sql once and tracks applied versions in
# ecosystem.schema_migrations. This installs the full schema + metric set and is
# the sole apply path — every metric/schema object lives in a migration.
#
# Mirror-node tables (public.transaction, public.token_transfer, erc.*, ...) are
# NOT set up here: they arrive on this subscriber via a Postgres logical
# replication subscription to the mirror node (the publisher). That subscription
# and the local table schema it replicates into must exist before the metric
# migrations run, since they reference those tables with check_function_bodies on.
bash /sql/migrations/migrate.sh

echo "[init] Done."
