#!/bin/bash
# =====================================================
# Hedera Stats - Database Initialization
# =====================================================
# Runs once when the Postgres container starts for the first time:
#   1. Creates extensions (timestamp9, postgres_fdw, http, pg_cron)
#   2. Sets up FDW server to the mirror node using env vars
#   3. Imports required mirror node tables as foreign tables
#   4. Creates ecosystem schema, tables, types
#   5. Loads all metric functions from /sql/metrics/
#   6. Loads metric descriptions and hbar_total_supply
#   7. Schedules pg_cron jobs
#
# Required env vars (from docker-compose .env):
#   MIRROR_NODE_HOST, MIRROR_NODE_PORT, MIRROR_NODE_DB,
#   MIRROR_NODE_USER, MIRROR_NODE_PASSWORD
# =====================================================

set -e

DB="${POSTGRES_DB:-hedera_stats}"
PSQL="psql -v ON_ERROR_STOP=1 --username $POSTGRES_USER --dbname $DB"
# pg_cron lives in the default "postgres" database (see docker-compose.yml
# cron.database_name). All other extensions and metric objects live in $DB.
PSQL_CRON="psql -v ON_ERROR_STOP=1 --username $POSTGRES_USER --dbname postgres"

echo "[init] Installing pg_cron in the postgres database..."
$PSQL_CRON <<SQL
CREATE EXTENSION IF NOT EXISTS pg_cron;
SQL

echo "[init] Running mirror node type definitions in $DB..."
$PSQL -f /docker-entrypoint-initdb.d/00-mirror-node-types.sql

echo "[init] Creating extensions in $DB..."
$PSQL <<SQL
CREATE EXTENSION IF NOT EXISTS timestamp9;
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE EXTENSION IF NOT EXISTS http;
SQL

echo "[init] Applying /sql/up.sql..."
$PSQL -f /sql/up.sql

echo "[init] Creating ecosystem.metric_description table..."
$PSQL <<SQL
CREATE TABLE IF NOT EXISTS ecosystem.metric_description (
  name text PRIMARY KEY,
  description text,
  methodology text
);
SQL

if [ -z "$MIRROR_NODE_HOST" ]; then
  echo "[init] WARN: MIRROR_NODE_HOST not set - skipping FDW setup. Mirror-node-backed metrics will not work."
else
  echo "[init] Setting up FDW to mirror node at $MIRROR_NODE_HOST:$MIRROR_NODE_PORT/$MIRROR_NODE_DB..."
  $PSQL <<SQL
CREATE SERVER IF NOT EXISTS mirror_node
  FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (
    host '$MIRROR_NODE_HOST',
    port '$MIRROR_NODE_PORT',
    dbname '$MIRROR_NODE_DB',
    fetch_size '50000'
  );

CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER
  SERVER mirror_node
  OPTIONS (
    user '$MIRROR_NODE_USER',
    password '$MIRROR_NODE_PASSWORD'
  );

-- Import required tables. Individual imports so a missing table doesn't
-- abort the whole load.
DO \$\$
DECLARE
  t text;
  tables text[] := ARRAY[
    'entity', 'transaction', 'crypto_transfer',
    'contract_result', 'contract_log',
    'token', 'nft_transfer', 'nft', 'nft_history'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    BEGIN
      EXECUTE format(
        'IMPORT FOREIGN SCHEMA public LIMIT TO (%I) FROM SERVER mirror_node INTO public',
        t
      );
      RAISE NOTICE '  imported: %', t;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '  skipped %: %', t, SQLERRM;
    END;
  END LOOP;
END \$\$;

-- Optionally import the erc schema if it exists on the mirror node
DO \$\$
BEGIN
  CREATE SCHEMA IF NOT EXISTS erc;
  BEGIN
    IMPORT FOREIGN SCHEMA erc FROM SERVER mirror_node INTO erc;
    RAISE NOTICE '  imported erc schema';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '  erc schema not available on mirror node (ok)';
  END;
END \$\$;
SQL
fi

echo "[init] Loading metric functions from /sql/metrics/..."
# avg_usd_conversion.sql still uses pg_http - kept in-database.
# hbar_total_supply.sql is a raw INSERT, handled after functions.
# legacy/, setup/ directories are skipped.
for pass in 1 2; do
  echo "[init]   pass $pass..."
  find /sql/metrics -type f -name '*.sql' \
    -not -path '*/legacy/*' \
    -not -path '*/setup/*' \
    -not -name 'hbar_total_supply.sql' \
    | while read -r file; do
        # Swap public.interval_granularity (mirror-node-only enum) for text.
        sed 's/public\.interval_granularity/text/g' "$file" \
          | $PSQL >/dev/null 2>&1 && echo "[init]     loaded $(basename $file)" \
          || true
      done
done

echo "[init] Loading metric descriptions..."
$PSQL -f /sql/metric_descriptions.sql || echo "[init]   (metric_descriptions had warnings - continuing)"

echo "[init] Seeding hbar_total_supply..."
$PSQL -f /sql/metrics/hbar-defi/hbar_total_supply.sql

echo "[init] Loading load_metrics procedures..."
for f in /sql/jobs/load_metrics_minute.sql \
         /sql/jobs/load_metrics_hour.sql \
         /sql/jobs/load_metrics_day.sql \
         /sql/jobs/load_metrics_week.sql \
         /sql/jobs/load_metrics_month.sql \
         /sql/jobs/load_metrics_quarter.sql \
         /sql/jobs/load_metrics_year.sql \
         /sql/jobs/load_metrics_init.sql \
         /sql/jobs/load_metrics_beta.sql \
         /sql/jobs/network_tvl.sql \
         /sql/jobs/stablecoin_marketcap.sql; do
  if [ -f "$f" ]; then
    $PSQL -f "$f" >/dev/null 2>&1 && echo "[init]   loaded $(basename $f)" || echo "[init]   skipped $(basename $f) (had errors)"
  fi
done

echo "[init] Scheduling pg_cron jobs (in postgres db, targeting $DB)..."
# pg_cron_metrics.sql uses <database_name> as a placeholder, and uses
# cron.schedule_in_database() so jobs run in the stats database even
# though pg_cron itself lives in the "postgres" database.
sed "s/<database_name>/$DB/g" /sql/jobs/pg_cron_metrics.sql | $PSQL_CRON

echo "[init] Done."
