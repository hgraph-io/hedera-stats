# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hedera Stats is an analytics platform for the Hedera network. It runs as a standalone Node.js/TypeScript application that connects to any Hedera mirror node database (read-only) and populates its own stats database with computed metrics. Deployable via Docker Compose.

**Important**: Claude does not have direct database access. When SQL queries need to be executed or tested, ask the user to run them and provide the results.

## Architecture

### Standalone App (Option C)

The app uses `postgres_fdw` (Foreign Data Wrapper) to give the stats database read-only access to mirror node tables. All existing SQL metric functions are created on the stats DB and query the mirror node transparently through foreign tables.

- **Stats DB** (Postgres, managed by Docker): `ecosystem` schema with metric tables + foreign tables to mirror node
- **Mirror Node DB** (external, read-only): accessed via `postgres_fdw`, zero modifications needed
- **App** (Node.js): handles setup, scheduling, API metrics, and orchestration

### Core Data Model

- **ecosystem.metric** - Central table storing all calculated metrics (columns: name, period, timestamp_range, total)
- **ecosystem.metric_total** - Return type for metric functions: `(int8range, total bigint)`
- **ecosystem.metric_description** - Metadata with name, description, and methodology

### Metric Types

1. **SQL metrics** - existing SQL functions (in `src/metrics/`), created on stats DB, query mirror node via fdw
2. **API metrics** - reimplemented in TypeScript (in `app/metrics/`), make HTTP calls to external APIs
3. **Derived metrics** - SQL functions that read from `ecosystem.metric` table only (e.g., hbar_market_cap)

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
app/                            # TypeScript application
├── index.ts                    # Entry point (--init, --run=<job>, or scheduler)
├── config.ts                   # Environment config
├── db.ts                       # Database connection pool
├── setup.ts                    # DB initialization (schema, fdw, functions)
├── sql-loader.ts               # Loads SQL files from src/metrics/
├── registry.ts                 # Metric-to-schedule mappings
├── runner.ts                   # Metric execution engine
├── scheduler.ts                # node-cron scheduler
└── metrics/                    # API metric implementations
    ├── avg-usd-conversion.ts   # Exchange price aggregation
    ├── network-tvl.ts          # DeFiLlama TVL
    └── stablecoin-marketcap.ts # DeFiLlama stablecoin data
src/
├── metrics/                    # SQL metric functions (loaded at startup)
│   ├── activity-engagement/    # active_accounts, new_accounts, total_accounts variants
│   ├── evm/                    # smart contracts, ECDSA real EVM accounts
│   ├── hbar-defi/              # price, market cap, supply metrics
│   ├── network-performance/    # network_fee, network_tps
│   ├── transactions/           # new_*/total_* transaction counts
│   └── non-fungible-tokens/    # NFT sales metrics
├── jobs/                       # Legacy load procedures (reference only)
├── grafana/                    # Dashboard configs
└── time-to-consensus/          # ETL for avg_time_to_consensus (uses Prometheus)
```

## Development Workflow

### Building and Running

```bash
npm install              # Install dependencies
npm run dev              # Run in development mode (tsx)
npm run build            # Compile TypeScript
npm start                # Run compiled app

# Docker
docker compose up -d     # Start stats-db + app
docker compose logs -f   # Follow logs

# CLI flags
npm run dev -- --init              # Run all jobs once (backfill)
npm run dev -- --run=hour          # Run a specific job once
```

### Adding a New Metric

1. Create function file in `src/metrics/<category>/<metric_name>.sql`
2. Add entry to `src/metric_descriptions.sql` with name, description, methodology
3. Add metric name to the appropriate job(s) in `app/registry.ts`
4. If API-based: create implementation in `app/metrics/` and add handler in `app/runner.ts`
5. Update CHANGELOG.md under "Unreleased" section

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

### Debugging

```sql
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

- Node.js/TypeScript app with SQL metric functions
- Stats DB extensions: timestamp9, postgres_fdw
- Mirror node: read-only access, no extensions or functions created
- API metrics (avg_usd_conversion, network_tvl, stablecoin_marketcap) are in TypeScript, not SQL
- Function names use `lowercase_snake_case` without category prefix
- Always test on testnet before mainnet
- CHANGELOG.md must be updated for all significant changes
