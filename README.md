# Hedera Stats: Shared Network Insights

**[Hedera Stats](https://docs.hgraph.com/hedera-stats/introduction)** is a PostgreSQL-based analytics platform that provides quantitative statistical measurements for the Hedera network. The platform calculates and stores metrics using SQL functions and procedures, leveraging open-source methodologies, Hedera mirror node data, third-party data sources, and Hgraph's GraphQL API. These statistics include network performance metrics, NFT analytics, account activities, and economic indicators, enabling transparent and consistent analysis of the Hedera ecosystem.

All metrics are pre-computed and stored in the `ecosystem.metric` table, with automated updates via pg_cron and visualization through Grafana dashboards.

- **[Experience the Grafana Demo →](https://hederastats.com)**
- [View Full Documentation →](https://docs.hgraph.com/hedera-stats)

## Getting Started

### Prerequisites

- **PostgreSQL database** (v14+) with the following extensions:
  - **pg_http** - For external API calls (HBAR price data, etc.)
  - **pg_cron** - For automated metric updates (requires superuser privileges)
  - **timestamp9** - For Hedera's nanosecond precision timestamps
- **Hedera Mirror Node** or access to **Hgraph's GraphQL API**
  - [Create a free account](https://hgraph.com/hedera)
- **Prometheus** (`promtool`) for `avg_time_to_consensus` ([download](https://prometheus.io/download/))
- **DeFiLlama API** for decentralized finance metrics ([view docs](https://defillama.com/docs/api))
- **Grafana** (optional) for visualization dashboards

### Installation

Clone this repository:

```bash
git clone https://github.com/hgraph-io/hedera-stats.git
cd hedera-stats
```

Install Prometheus CLI (`promtool`):

```bash
curl -L -O https://github.com/prometheus/prometheus/releases/download/v3.1.0/prometheus-3.1.0.linux-amd64.tar.gz
tar -xvf prometheus-3.1.0.linux-amd64.tar.gz
cp prometheus-3.1.0.linux-amd64/promtool /usr/bin
```

### Initial Configuration

Set up your database. The schema and every metric live in ordered migrations
under `src/migrations/`; the runner applies each once and tracks it in
`ecosystem.schema_migrations`. The migrations are pure schema SQL — the
`timestamp9` and `http` extensions and the logical replication subscription are
external prerequisites, installed by a superuser beforehand.

**Deploy into a co-located network database** (ecosystem alongside the replicated
mirror-node tables), over the Unix socket with objects owned by the per-network
`ecosystem_owner` role:

```bash
src/migrations/deploy.sh mainnet          # dry run — prints the plan
src/migrations/deploy.sh mainnet --run    # execute (mainnet: 5433/hedera_mainnet)
src/migrations/deploy.sh testnet --run    # testnet: 5432/hedera_testnet
```

Under Docker this runs automatically on first boot (`migrate.sh` is mounted into
`/docker-entrypoint-initdb.d`). It connects over the Unix socket, so no password
is needed. To apply new migrations to a running container later:

```bash
docker compose exec stats-db bash /sql/migrations/migrate.sh
```

Already-applied migrations are skipped. To run against a database outside Docker,
override the libpq vars (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, and
`PGPASSWORD` if not using socket/trust auth):

```bash
PGHOST=localhost PGPORT=5433 PGDATABASE=hedera_stats PGUSER=postgres \
  bash src/migrations/migrate.sh /path/to/src/migrations
```

> `pg_cron` scheduling (`src/jobs/pg_cron_metrics.sql`) is **not** applied by the
> migration runner. It drives metric loading and belongs on the publisher.

Configure environment variables (create `.env` file):

```env
# Database connection
DATABASE_URL="postgresql://user:password@localhost:5432/hedera_stats"
POSTGRES_CONNECTION_STRING="postgresql://user:password@localhost:5432/hedera_stats"

# API Keys
HGRAPH_API_KEY="your_api_key"

# Prometheus (for avg_time_to_consensus)
PROMETHEUS_ENDPOINT="https://your-prometheus-endpoint"
```

Schedule automated updates:

1. **pg_cron for metric updates**:
   ```bash
   # Edit src/jobs/pg_cron_metrics.sql
   # Replace <database_name> and <database_user> with your database name and database user
   psql -d your_database -f src/jobs/pg_cron_metrics.sql
   ```

2. **Time-to-consensus updates** (if using Prometheus):
   ```bash
   crontab -e
   # Add these entries:
   # Hourly collection
   1 * * * * cd /path/to/hedera-stats/src/time-to-consensus && bash ./run.sh >> ./.raw/cron.log 2>&1
   # Daily collection
   2 0 * * * cd /path/to/hedera-stats/src/time-to-consensus && bash ./run_day.sh >> ./.raw/cron_day.log 2>&1
   ```

## Repository Structure

```
hedera-stats/
├── src/
│   ├── migrations/                 # SOLE apply path: NNN-name.sql, applied once each in order
│   │   ├── migrate.sh              # Runner: applies unapplied migrations, tracks in schema_migrations
│   │   ├── 001-init.sql            # Schema, tables, metric_total type, row helpers
│   │   └── 0NN-*.sql               # One migration per function / description / seed / load procedure
│   ├── metric_descriptions.sql     # Readable source (generated into a migration; not loaded at runtime)
│   ├── grafana/                    # Grafana dashboard JSON exports
│   │   └── Hgraph_Hedera-Stats-Grafana_V2.json
│   ├── jobs/                       # Job procedures and scheduling
│   │   ├── load_metrics_minute.sql # High-frequency price updates
│   │   ├── load_metrics_hour.sql   # Hourly loader (23 metrics)
│   │   ├── load_metrics_day.sql    # Daily loader (38 metrics)
│   │   ├── load_metrics_week.sql   # Weekly aggregations
│   │   ├── load_metrics_month.sql  # Monthly aggregations
│   │   ├── load_metrics_quarter.sql
│   │   ├── load_metrics_year.sql
│   │   ├── load_metrics_init.sql   # Backfill/initialization
│   │   └── pg_cron_metrics.sql     # Cron job definitions
│   ├── metrics/                    # Metric calculation functions
│   │   ├── activity-engagement/    # Account activity metrics
│   │   ├── evm/                    # Smart contract metrics
│   │   ├── hbar-defi/              # Price & supply metrics
│   │   ├── network-performance/    # Fee & TPS metrics
│   │   ├── transactions/           # Transaction count metrics
│   │   └── non-fungible-tokens/    # NFT sales metrics
│   └── time-to-consensus/          # Prometheus ETL pipeline
├── CLAUDE.md                       # AI assistant guidance
├── WORKFLOW.md                     # Development workflow
├── CHANGELOG.md                    # Version history
├── LICENSE
└── README.md
```

## Architecture

### Core Data Model

- **ecosystem.metric** - Central table storing all calculated metrics
  - Columns: `name`, `period`, `timestamp_range` (int8range), `total` (bigint)
  - Unique constraint: `(name, period, timestamp_range)`
- **ecosystem.metric_total** - Standard return type for metric functions: `(int8range, total)`
- **ecosystem.metric_description** - Metadata with name, description, and methodology

### Metric Function Signature

All metric functions follow this standard signature:

```sql
CREATE OR REPLACE FUNCTION ecosystem.<metric_name>(
    period TEXT,                    -- 'minute','hour','day','week','month','quarter','year'
    start_timestamp BIGINT DEFAULT 0,
    end_timestamp BIGINT DEFAULT CURRENT_TIMESTAMP::timestamp9::BIGINT
) RETURNS SETOF ecosystem.metric_total
```

### Data Processing Pipeline

1. **External Data Sources** → PostgreSQL via pg_http or mirror node tables
2. **Metric Functions** → Calculate metrics using SQL/PL/pgSQL
3. **Job Procedures** → Orchestrate metric loading via stored procedures
4. **pg_cron Jobs** → Automate execution on schedule
5. **ecosystem.metric table** → Store pre-computed results
6. **Grafana Dashboards / GraphQL API** → Query and visualize metrics

## Available Metrics

### Metric Categories

| Category | Count | Examples |
|----------|-------|----------|
| Activity & Engagement | 11 | `active_accounts`, `new_accounts`, `total_accounts`, `*_ecdsa_*`, `*_ed25519_*` |
| EVM/Smart Contracts | 5 | `active_smart_contracts`, `new_smart_contracts`, `*_ecdsa_accounts_real_evm` |
| HBAR & DeFi | 4 | `avg_usd_conversion`, `hbar_market_cap`, `hbar_total_released`, `hbar_total_supply` |
| Network Performance | 4 | `network_fee`, `avg_network_fee`, `network_tps`, `avg_time_to_consensus` |
| Transactions | 14+ | `new_transactions`, `total_hcs_transactions`, `new_crypto_transactions` |
| NFTs | 2 | `nft_collection_sales_volume`, `nft_collection_sales_volume_total` |

[**View all metrics & documentation →**](https://docs.hgraph.com/category/hedera-stats)

### Supported Periods

| Period | Description | Typical Use Case |
|--------|-------------|------------------|
| `minute` | Per-minute data | High-frequency price tracking (72h retention) |
| `hour` | Hourly aggregates | Real-time monitoring |
| `day` | Daily aggregates | Standard reporting |
| `week` | Weekly aggregates | Trend analysis |
| `month` | Monthly aggregates | Monthly reports |
| `quarter` | Quarterly aggregates | Quarterly reports |
| `year` | Yearly aggregates | Annual comparisons |

### Cron Schedule

| Job | Schedule | Time (UTC) |
|-----|----------|------------|
| Minute | `* * * * *` | Every minute |
| Hour | `1 * * * *` | :01 past each hour |
| Day | `2 0 * * *` | 00:02 daily |
| Week | `2 0 * * 0` | 00:02 Sundays |
| Month | `4 0 1 * *` | 00:04 on 1st |
| Quarter | `8 0 1 1,4,7,10 *` | 00:08 on Jan/Apr/Jul/Oct 1st |
| Year | `14 0 1 1 *` | 00:14 on Jan 1st |

## Usage Examples

### Query Pre-Computed Metrics

```sql
-- Query metrics from the ecosystem.metric table
SELECT *
FROM ecosystem.metric
WHERE name = 'active_accounts'
  AND period = 'day'
ORDER BY timestamp_range DESC
LIMIT 20;
```

### Test Metric Functions Directly

```sql
-- Call a metric function with time range
SELECT * FROM ecosystem.active_accounts(
    'day',
    (current_timestamp - interval '7 days')::timestamp9::bigint,
    current_timestamp::timestamp9::bigint
);

-- Check job execution status
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
```

### Run Load Procedures Manually

```sql
-- Run a specific period's loader
CALL ecosystem.load_metrics_hour();
CALL ecosystem.load_metrics_day();

-- Backfill/initialize metrics
CALL ecosystem.load_metrics_init();
```

### Custom Grafana Dashboard

Use Grafana to visualize metrics:

1. Import `Hgraph_Hedera-Stats-Grafana_V2.json` from `src/grafana/`
2. Configure PostgreSQL data source pointing to your database
3. Dashboards query `ecosystem.metric` table directly

### Fetching Metrics via GraphQL API

Query available metrics dynamically via GraphQL API ([test in our developer playground](https://dashboard.hgraph.com)):

```graphql
query AvailableMetrics {
  ecosystem_metric(distinct_on: name) {
    name
    description {
      description
      methodology
    }
  }
}
```

## Troubleshooting & FAQs

### Missing data or discrepancies?

- Verify you're querying the correct API endpoint:
  - Staging environment (`hgraph.dev`) may have incomplete data
  - Production endpoint (`hgraph.io`) requires an API key

### Job not running?

```sql
-- Check scheduled cron jobs
SELECT * FROM cron.job;

-- Check recent job execution history
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
```

### Metric returning NULL or empty?

```sql
-- Verify the metric function exists
\df ecosystem.<metric_name>

-- Check if metric is in the load procedure's array
-- (review src/jobs/load_metrics_<period>.sql)

-- Test the function directly
SELECT * FROM ecosystem.<metric_name>(
    'day',
    (current_timestamp - interval '30 days')::timestamp9::bigint,
    current_timestamp::timestamp9::bigint
);
```

### Improve query performance

- Use broader granularity (day/month) for extensive time periods
- Limit result size with `LIMIT` and filter by `period`
- Query pre-computed data from `ecosystem.metric` instead of calling functions directly

## Additional Resources

- [**Full Hedera Stats Documentation →**](https://docs.hgraph.com/category/hedera-stats)
- [Hedera Mirror Node Docs](https://docs.hedera.com/hedera/core-concepts/mirror-nodes)
- [Hedera Transaction Result Codes](https://github.com/hashgraph/hedera-mirror-node/blob/main/hedera-mirror-rest/model/transactionResult.js)
- [Hedera Transaction Types](https://github.com/hashgraph/hedera-mirror-node/blob/main/hedera-mirror-rest/model/transactionType.js)
- [DeFiLlama API Documentation](https://defillama.com/docs/api)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/current/)

## Contribution Guidelines

We welcome contributions!

1. Fork this repository
2. Create your feature branch (`git checkout -b feature/new-metric`)
3. Commit changes (`git commit -am 'Add new metric'`)
4. Push to the branch (`git push origin feature/new-metric`)
5. Submit a Pull Request detailing your changes

See [WORKFLOW.md](WORKFLOW.md) for detailed development guidelines.

## License

[Apache License 2.0](https://github.com/hgraph-io/hedera-stats/blob/main/LICENSE)
