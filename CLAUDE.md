# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hedera Stats is a PostgreSQL-based analytics platform for the Hedera network. It runs as a standalone Postgres container that connects to any Hedera mirror node database (read-only) via `postgres_fdw` and populates its own `ecosystem` schema with computed metrics. Deployable via Docker Compose.

**Important**: Claude does not have direct database access. When SQL queries need to be executed or tested, ask the user to run them and provide the results.

## Architecture

Everything runs inside the stats database. There is no application layer - the container is just Postgres with a set of extensions, metric functions, and pg_cron schedules.

- **Stats DB** (Postgres, managed by Docker): owns the `ecosystem` schema (metric tables, functions, pg_cron jobs) and foreign tables proxying to the mirror node
- **Mirror Node DB** (external, read-only): accessed via `postgres_fdw`, zero modifications needed

The stats container uses these Postgres extensions:
- `timestamp9` - nanosecond timestamp support (Hedera)
- `postgres_fdw` - foreign tables proxying to mirror node
- `http` (pg_http) - outbound HTTP calls for API-based metrics (exchange prices, DeFiLlama)
- `pg_cron` - scheduler for metric load procedures

### Core Data Model

- **ecosystem.metric** - Central table storing all calculated metrics (columns: name, period, timestamp_range, total)
- **ecosystem.metric_total** - Return type for metric functions: `(int8range, total bigint)`
- **ecosystem.metric_description** - Metadata with name, description, and methodology

### Metric Function Signature

All metric functions use this standard signature (note: function names do NOT include category prefix):

```sql
CREATE OR REPLACE FUNCTION ecosystem.<metric_name>(
    period TEXT,                    -- 'minute', 'hour', 'day', 'week', 'month', 'quarter', 'year'
    start_timestamp BIGINT DEFAULT 0,
    end_timestamp BIGINT DEFAULT CURRENT_TIMESTAMP::timestamp9::BIGINT
) RETURNS SETOF ecosystem.metric_total
```

### Key Directories

```
docker/
└── postgres/
    ├── Dockerfile              # postgres:16 + timestamp9 + pg_cron + pg_http
    └── init/
        ├── 00-mirror-node-types.sql  # Enum/domain types needed for FDW imports
        └── 01-init.sh                # Extensions, FDW setup, loads /sql/*

src/
├── up.sql                      # Schema + extensions + metric table
├── metric_descriptions.sql     # Seeds metric_description metadata
├── metrics/                    # SQL metric functions by category
│   ├── activity-engagement/    # active_accounts, new_accounts, total_accounts variants
│   ├── evm/                    # smart contracts, ECDSA real EVM accounts
│   ├── hbar-defi/              # price, market cap, supply metrics (uses pg_http)
│   ├── network-performance/    # network_fee, network_tps
│   ├── transactions/           # new_*/total_* transaction counts
│   └── non-fungible-tokens/    # NFT sales metrics
├── jobs/                       # Load procedures and pg_cron scheduling
│   ├── load_metrics_hour.sql   # Hourly loader procedure
│   ├── load_metrics_day.sql    # Daily loader procedure
│   ├── network_tvl.sql         # DeFiLlama TVL (uses pg_http)
│   ├── stablecoin_marketcap.sql # DeFiLlama stablecoin (uses pg_http)
│   └── pg_cron_metrics.sql     # Cron job definitions
├── grafana/                    # Dashboard configs
└── time-to-consensus/          # ETL for avg_time_to_consensus (uses Prometheus)
```

## Development Workflow

### Running

```bash
cp .env.example .env     # fill in MIRROR_NODE_* credentials
docker compose up -d     # starts stats-db; init script runs on first start
docker compose logs -f stats-db
```

### Adding a New Metric

1. Create function file in `src/metrics/<category>/<metric_name>.sql`
2. Add entry to `src/metric_descriptions.sql` with name, description, methodology
3. Add metric name to the `metrics` array in the relevant `src/jobs/load_metrics_<period>.sql` procedures
4. Update `src/jobs/pg_cron_metrics.sql` if scheduling changes needed
5. Update CHANGELOG.md under "Unreleased" section

On next `docker compose up` with a fresh volume, the new metric is picked up automatically. On an existing deployment, either re-run the relevant file via `docker compose exec stats-db psql -f /sql/metrics/...` or recreate the volume.

### Testing Metric Functions

```sql
-- Standard test pattern (run against stats DB)
SELECT * FROM ecosystem.<metric_name>(
    'day',
    (current_timestamp - interval '7 days')::timestamp9::bigint,
    current_timestamp::timestamp9::bigint
);

-- Verify stored data
SELECT * FROM ecosystem.metric
WHERE name = '<metric_name>' AND period = 'day'
ORDER BY timestamp_range DESC LIMIT 10;
```

### Running Load Procedures

```sql
-- Run a specific period's loader
CALL ecosystem.load_metrics_hour();
CALL ecosystem.load_metrics_day();

-- Backfill/initialize metrics (runs all periods)
CALL ecosystem.load_metrics_init();
```

### Debugging

```sql
-- View cron job status
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- Check loaded functions on stats DB
SELECT proname FROM pg_proc WHERE pronamespace = 'ecosystem'::regnamespace;

-- Check foreign tables (mirror node connection)
SELECT foreign_table_name FROM information_schema.foreign_tables;

-- View function definition
SELECT pg_get_functiondef(p.oid) FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'ecosystem' AND p.proname = '<function_name>';
```

## SQL Patterns

### Timestamp Handling

Hedera uses nanosecond timestamps. Convert using timestamp9 extension:
```sql
-- Current time as bigint
current_timestamp::timestamp9::bigint

-- Bigint to readable timestamp
(timestamp_value)::timestamp9::timestamp

-- Period truncation
date_trunc('day', to_timestamp(created_timestamp / 1e9))
```

### Int8range for Time Intervals

```sql
INT8RANGE(
    period_start::timestamp9::bigint,
    (period_start + INTERVAL '1 day')::timestamp9::bigint
)
```

### Cumulative vs Period Metrics

- **new_*** metrics: Count within each period (use `BETWEEN start_timestamp AND end_timestamp`)
- **total_*** metrics: Cumulative count up to period end (sum of all previous new_* values or direct count to end)
- **active_*** metrics: Distinct entities active during the period

## Important Notes

- Pure SQL/PostgreSQL project - everything runs inside the database
- Stats DB extensions: timestamp9, postgres_fdw, http, pg_cron
- Mirror node: read-only access, no extensions or functions created there
- Function names use `lowercase_snake_case` without category prefix
- Always test on testnet before mainnet
- CHANGELOG.md must be updated for all significant changes
