# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hedera Stats is a PostgreSQL-based analytics platform for the Hedera network. It runs as a Postgres container that is a **logical replication subscriber** to a Hedera mirror node (the publisher): mirror-node tables are replicated in as local tables, and the container computes its own `ecosystem` schema of metrics on top of them. Deployable via Docker Compose.

**Important**: Claude does not have direct database access. When SQL queries need to be executed or tested, ask the user to run them and provide the results.

## Architecture

Everything runs inside the stats database. There is no application layer - the container is just Postgres with a set of extensions and metric functions.

- **Stats DB** (Postgres, managed by Docker): a logical replication subscriber. Owns the `ecosystem` schema (metric tables, functions) and receives mirror-node tables (`public.transaction`, `public.token_transfer`, `erc.*`, ...) via a subscription.
- **Mirror Node DB** (external): the publisher. The subscription and the local schema it replicates into are **provisioned outside this repo**; this container assumes those tables are present when metric migrations run.

The stats container uses these Postgres extensions:
- `timestamp9` - nanosecond timestamp support (Hedera)
- `http` (pg_http) - outbound HTTP calls for API-based metrics (exchange prices, DeFiLlama)

`pg_cron` (scheduling) belongs on the publisher, not this subscriber.

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
    └── Dockerfile              # postgres:16 + timestamp9 + pg_http
                                # (first boot mounts src/migrations/migrate.sh into
                                #  /docker-entrypoint-initdb.d — see docker-compose.yml)

src/
├── migrations/                 # SOLE apply path: NNN-name.sql, applied once each in order
│   ├── migrate.sh              # Runner: applies unapplied migrations, tracks in schema_migrations
│   ├── 001-init.sql            # Schema + metric/metric_description tables + type + helpers
│   └── 0NN-*.sql               # One migration per function / description / seed / load procedure
├── metric_descriptions.sql     # Readable source (generated into a migration; not loaded at runtime)
├── metrics/                    # Readable source for metric functions (generated into migrations)
│   ├── activity-engagement/    # active_accounts, new_accounts, total_accounts variants
│   ├── evm/                    # smart contracts, ECDSA real EVM accounts
│   ├── hbar-defi/              # price, market cap, supply metrics (uses pg_http)
│   ├── network-performance/    # network_fee, network_tps
│   ├── transactions/           # new_*/total_* transaction counts
│   └── non-fungible-tokens/    # NFT sales metrics
├── jobs/                       # Load procedures (source) + pg_cron_metrics.sql (publisher-only)
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

### Migrations

`src/migrations/` is the **sole apply path**. Every schema object and metric —
the schema skeleton (`001-init.sql`), each metric function, the descriptions,
the seed, and each load procedure — is its own `NNN-name.sql` migration. The
runner (`src/migrations/migrate.sh`) applies unapplied migrations in filename
order and records each in `ecosystem.schema_migrations`, so each runs exactly
once, on fresh boot and on live subscribers alike.

Ordering matters: migrations run with `check_function_bodies` ON, so a function
is validated against everything it references at CREATE time. A migration must
come after the migrations that define the `ecosystem.*` functions it calls. The
baseline migrations (`002`+) were generated in dependency order; keep new ones
after their dependencies.

`src/metrics/`, `src/metric_descriptions.sql`, and `src/jobs/*.sql` remain as the
**readable source** the baseline migrations were generated from. They are NOT
loaded at runtime — do not edit them expecting a change to take effect.

`src/jobs/pg_cron_metrics.sql` is **not** a migration and is not applied to a
subscriber. Cron drives metric loading and belongs on the **publisher**.

### Adding a New Metric

1. Create `src/migrations/NNN-<metric_name>.sql` (next number, after any migration
   defining a function it calls) containing everything the metric needs:
   - `CREATE OR REPLACE FUNCTION ecosystem.<metric_name>(...)`
   - `INSERT INTO ecosystem.metric_description (...) ON CONFLICT (name) DO UPDATE ...`
   - a `CREATE OR REPLACE PROCEDURE` migration for any `load_metrics_<period>` change
2. Update CHANGELOG.md under "Unreleased"

To change an existing object, add a NEW migration that `CREATE OR REPLACE`s it —
never edit an applied migration.

Apply it:
- **Fresh volume**: `docker compose up` runs migrate.sh automatically.
- **Live subscriber**: `docker compose exec stats-db bash /sql/migrations/migrate.sh` — no volume recreation.

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

-- Check replicated mirror-node tables are present (from the logical subscription)
SELECT schemaname, tablename FROM pg_tables WHERE schemaname IN ('public','erc') ORDER BY 1,2;
-- Subscription status (if the subscription is on this DB)
SELECT subname, subenabled FROM pg_subscription;

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
- Stats DB extensions: timestamp9, http
- Mirror-node tables arrive via a logical replication subscription (provisioned outside this repo); the stats DB does not connect to the mirror node via FDW
- Function names use `lowercase_snake_case` without category prefix
- Always test on testnet before mainnet
- CHANGELOG.md must be updated for all significant changes
