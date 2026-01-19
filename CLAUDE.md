# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hedera Stats is a PostgreSQL-based analytics platform for the Hedera network that calculates and stores quantitative metrics using SQL functions and procedures. The project uses Grafana for visualization and pg_cron for automated metric updates.

**Important**: Claude does not have direct database access. When SQL queries need to be executed or tested, ask the user to run them and provide the results.

## Architecture

### Core Data Model

- **ecosystem.metric** - Central table storing all calculated metrics (columns: name, period, timestamp_range, total)
- **ecosystem.metric_total** - Return type for metric functions: `(int8range, total bigint)`
- **ecosystem.metric_description** - Metadata with name, description, and methodology

### Metric Function Signature

All metric functions use this standard signature (note: function names do NOT include category prefix):

```sql
CREATE OR REPLACE FUNCTION ecosystem.<metric_name>(
    period TEXT,                    -- 'hour', 'day', 'week', 'month', 'quarter', 'year'
    start_timestamp BIGINT DEFAULT 0,
    end_timestamp BIGINT DEFAULT CURRENT_TIMESTAMP::timestamp9::BIGINT
) RETURNS SETOF ecosystem.metric_total
```

### Job Procedure Pattern

Load procedures in `src/jobs/load_metrics_<period>.sql` iterate over a metrics array, dynamically calling each function and upserting results into ecosystem.metric. Each period has its own procedure (hour, day, week, month, quarter, year, minute).

### Key Directories

```
src/
├── metrics/                    # Metric functions by category
│   ├── activity-engagement/    # active_accounts, new_accounts, total_accounts variants
│   ├── evm/                    # smart contracts, ECDSA real EVM accounts
│   ├── hbar-defi/              # price, market cap, supply metrics
│   ├── network-performance/    # network_fee, network_tps
│   ├── transactions/           # new_*/total_* transaction counts
│   └── non-fungible-tokens/    # NFT sales metrics
├── jobs/                       # Load procedures and pg_cron scheduling
│   ├── load_metrics_hour.sql   # Hourly loader procedure
│   ├── load_metrics_day.sql    # Daily loader procedure
│   └── pg_cron_metrics.sql     # Cron job definitions
├── grafana/                    # Dashboard configs
└── time-to-consensus/          # ETL for avg_time_to_consensus (uses Prometheus)
```

## Development Workflow

### Adding a New Metric

1. Create function file in `src/metrics/<category>/<metric_name>.sql`
2. Add entry to `src/metric_descriptions.sql` with name, description, methodology
3. Add metric name to the `metrics` array in relevant `src/jobs/load_metrics_<period>.sql` procedures
4. Update `src/jobs/pg_cron_metrics.sql` if scheduling changes needed
5. Update CHANGELOG.md under "Unreleased" section

### Testing Metric Functions

```sql
-- Standard test pattern
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

### Debugging Jobs

```sql
-- View cron job status
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- Check loaded procedures
SELECT proname FROM pg_proc WHERE pronamespace = 'ecosystem'::regnamespace;

-- View procedure definition
SELECT pg_get_functiondef(p.oid) FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'ecosystem' AND p.proname = '<procedure_name>';
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

- Pure SQL/PostgreSQL project - no npm/package.json
- PostgreSQL extensions required: pg_cron, timestamp9, http (pg_http)
- Function names use `lowercase_snake_case` without category prefix in the function name itself
- Always test on testnet before mainnet
- CHANGELOG.md must be updated for all significant changes
