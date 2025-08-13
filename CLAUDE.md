# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hedera Stats is a PostgreSQL-based analytics platform for the Hedera network that calculates and stores quantitative metrics using SQL functions and procedures. The project uses Grafana for visualization and pg_cron for automated metric updates.

## Working with this Codebase

**Important**: Claude does not have direct database access. When SQL queries need to be executed or tested, ask the user to run them and provide the results.

## Common SQL Patterns to Generate

### Querying Pre-Computed Metrics
```sql
-- Query the pre-computed metrics from ecosystem.metric table
SELECT *
FROM ecosystem.metric
WHERE name = '<metric_name>'
ORDER BY timestamp_range DESC
LIMIT 20;

-- Example:
SELECT *
FROM ecosystem.metric
WHERE name = 'new_transactions'
ORDER BY timestamp_range DESC
LIMIT 20;
```

### Testing Metric Functions
```sql
-- Test a metric function with standard signature
SELECT * FROM ecosystem.metric_<category>_<name>('<network>', '<time_range>');

-- Example:
SELECT * FROM ecosystem.metric_activity_active_accounts('mainnet', 'hour');

-- Test functions that return ecosystem.metric_total type
-- (Note: These use different parameters than standard metrics)
SELECT * FROM ecosystem.total_ecdsa_accounts_real_evm(
    'day',  -- period: hour, day, week, month, quarter, year
    (current_timestamp - interval '30 days')::timestamp9::bigint,  -- start_timestamp
    current_timestamp::timestamp9::bigint  -- end_timestamp
);

-- Example testing new account metrics
SELECT * FROM ecosystem.new_ecdsa_accounts_real_evm(
    'week',
    (current_timestamp - interval '3 months')::timestamp9::bigint,
    current_timestamp::timestamp9::bigint
);
```

### Checking Job Status
```sql
-- View recent cron job runs
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- Check specific metric data with filters
SELECT * 
FROM ecosystem.metric 
WHERE name = '<metric_name>' 
  AND time_range = '<time_range>'
  AND network = '<network>'
ORDER BY timestamp_range DESC 
LIMIT 5;
```

## Architecture

### Core Data Model
- **ecosystem.metric** - Central table storing all calculated metrics with time ranges
- **ecosystem.metric_total** - Standard return type for metric functions: (int8range, total)
  - `int8range`: PostgreSQL range type for timestamp boundaries
  - `total`: Bigint value representing the metric count/value
- **ecosystem.metric_description** - Metadata and descriptions for each metric

### Metric Function Pattern

All metric functions follow this signature:
```sql
CREATE OR REPLACE FUNCTION ecosystem.metric_<category>_<name>(
    <network> TEXT,
    <time_range> TEXT
) RETURNS SETOF ecosystem.metric_total
```

### Data Processing Pipeline

1. **External Data Sources** → PostgreSQL via pg_http or mirror node tables
2. **Metric Functions** → Calculate metrics using SQL/PL/pgSQL
3. **Job Procedures** → Orchestrate metric loading via stored procedures
4. **pg_cron Jobs** → Automate execution on schedule
5. **ecosystem.metric table** → Store pre-computed results
6. **Grafana Dashboards** → Visualize metrics via SQL queries

### Key Directories

- `src/metrics/` - Metric calculation functions organized by category
- `src/jobs/` - Automated loading procedures and cron job definitions
- `src/dashboard/` - Grafana dashboard configurations and queries
- `src/time-to-consensus/` - Specialized ETL for consensus time metrics

## Development Workflow

### Adding New Metrics

1. Create function in appropriate `src/metrics/<category>/` directory
2. Add description to `src/metric_descriptions.sql`
3. Update job procedure in `src/jobs/procedures/` to call new function
4. Ask user to test: `SELECT * FROM ecosystem.metric_<category>_<name>('mainnet', 'hour')`
5. Schedule in `src/jobs/pg_cron_metrics.sql` if needed
6. Verify data is stored: `SELECT * FROM ecosystem.metric WHERE name = '<metric_name>' ORDER BY timestamp_range DESC LIMIT 5`

### SQL Development Guidelines

- Generate complete SQL functions with proper error handling
- Use JSONB for metadata storage in metric_metadata field
- Follow existing naming conventions: `metric_<category>_<name>`
- Include appropriate time range handling (hour, day, week, month, quarter, year)
- Use timestamp9 type for Hedera nanosecond precision when needed

## Important Notes

- This is a pure SQL/PostgreSQL project - no npm/Node.js dependencies
- All business logic is implemented in SQL/PL/pgSQL functions
- External API calls use pg_http extension within PostgreSQL
- Timestamp handling uses timestamp9 extension for Hedera's nanosecond precision
- Job scheduling uses pg_cron extension - requires database superuser privileges
- When debugging or testing SQL, ask the user to execute queries and provide results
