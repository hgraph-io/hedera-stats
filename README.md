# Hedera Stats: Shared Ecosystem and Network Insights

**[Hedera Stats](https://docs.hgraph.com/hedera-stats/introduction)** is a PostgreSQL-based analytics platform that provides quantitative statistical measurements for the Hedera network. The platform calculates and stores metrics using SQL functions and procedures, leveraging open-source methodologies, Hedera mirror node data, third-party data sources, and Hgraph's GraphQL API. These statistics include network performance metrics, NFT analytics, account activities, and economic indicators, enabling transparent and consistent analysis of the Hedera ecosystem.

All metrics are pre-computed and stored in the `ecosystem.metric` table, with automated updates via pg_cron and visualization through Grafana dashboards.

**[📖 View Full Documentation →](https://docs.hgraph.com/category/hedera-stats)**

## Getting Started

### Prerequisites

- **PostgreSQL database** (v14+) with the following extensions:
  - **pg_http** - For external API calls (HBAR price data, etc.)
  - **pg_cron** - For automated metric updates (requires superuser privileges)
  - **timestamp9** - For Hedera's nanosecond precision timestamps
- **Hedera Mirror Node** or access to **Hgraph's GraphQL API**
  - [Create a free account](https://hgraph.com/hedera)
- **Prometheus** (`promtool`) for `avg_time_to_consensus` ([view docs](https://prometheus.io/docs/introduction/overview/))
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
# one way to add the tool to the PATH
cp prometheus-3.1.0.linux-amd64/promtool /usr/bin
```

### Initial Configuration

Set up your database:

1. **Create schema and tables**:
   ```sql
   -- Execute the setup script
   psql -d your_database -f src/setup/up.sql
   ```

2. **Load metric functions and procedures**:
   - Execute SQL scripts from `src/metrics/` directories
   - Load job procedures from `src/jobs/procedures/`
   - Initialize metric descriptions from `src/metric_descriptions.sql`

Configure environment variables (example `.env`):

```env
DATABASE_URL="postgresql://user:password@localhost:5432/hedera_stats"
HGRAPH_API_KEY="your_api_key"
```

Schedule automated updates:

1. **pg_cron for metric updates**:
   ```sql
   -- Edit src/jobs/pg_cron_metrics.sql
   -- Replace <database_name> and <database_user> placeholders
   psql -d your_database -f src/jobs/pg_cron_metrics.sql
   ```

2. **Time-to-consensus updates** (if using Prometheus):
   ```bash
   crontab -e
   1 * * * * cd /path/to/hedera-stats/src/time-to-consensus && bash ./run.sh >> ./.raw/cron.log 2>&1
   ```

## Repository Structure

```markdown
hedera-stats/
├── src/
│   ├── dashboard/             # Grafana dashboards and SQL queries
│   ├── jobs/                  # Automated data loading and scheduling
│   ├── metrics/               # Metric calculation SQL functions
│   ├── setup/                 # Database schema setup
│   └── time-to-consensus/     # Consensus time metrics ETL
├── CLAUDE.md                  # AI assistant guidance
├── LICENSE
└── README.md
```

## Architecture

### Core Data Model

- **ecosystem.metric** - Central table storing all calculated metrics with time ranges
- **ecosystem.metric_total** - Standard return type for metric functions: (metric_timestamp, metric_value, metric_metadata)
- **ecosystem.metric_description** - Metadata and descriptions for each metric

### Data Processing Pipeline

1. **External Data Sources** → PostgreSQL via pg_http or mirror node tables
2. **Metric Functions** → Calculate metrics using SQL/PL/pgSQL
3. **Job Procedures** → Orchestrate metric loading via stored procedures
4. **pg_cron Jobs** → Automate execution on schedule
5. **ecosystem.metric table** → Store pre-computed results
6. **Grafana Dashboards** → Visualize metrics via SQL queries

## Available Metrics & Usage

Metrics categories include:

- Accounts & Network Participants
- NFT-specific Metrics
- Network Performance & Economic Metrics

[**View all metrics & documentation →**](https://docs.hgraph.com/category/hedera-stats)

### Usage Example: Query Pre-Computed Metrics

```sql
-- Query the pre-computed metrics from ecosystem.metric table
SELECT *
FROM ecosystem.metric
WHERE name = '<metric_name>'
ORDER BY timestamp_range DESC
LIMIT 20;
```

### Usage Example: Test Metric Functions

```sql
-- Test a metric function directly
SELECT * FROM ecosystem.metric_activity_active_accounts('mainnet', 'hour');

-- Check job status
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
```

### Usage Example: Custom Grafana Dashboard

Use Grafana to visualize metrics:

- Import `Hedera_KPI_Dashboard.json` from `src/dashboard`.
- SQL queries provided in the same directory serve as data sources.

### Usage Example: Fetching Metrics via GraphQL API

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
  - Staging environment (`hgraph.dev`) may have incomplete data.
  - Production endpoint (`hgraph.io`) requires an API key.

### Improve query performance

- Use broader granularity (day/month) for extensive periods.
- Limit result size with `limit` and `order_by`.
- Cache frequently accessed data.

## Additional Resources

- [**Full Hedera Stats Documentation →**](https://docs.hgraph.com/category/hedera-stats)
- [Hedera Mirror Node Docs](https://docs.hedera.com/hedera/core-concepts/mirror-nodes)
- [Hedera Transaction Result Codes](https://github.com/hashgraph/hedera-mirror-node/blob/main/hedera-mirror-rest/model/transactionResult.js)
- [Hedera Transaction Types](https://github.com/hashgraph/hedera-mirror-node/blob/main/hedera-mirror-rest/model/transactionType.js)
- [DeFiLlama API Documentation](https://defillama.com/docs/api)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/current/)

## Contribution Guidelines

We welcome contributions!

1. Fork this repository.
2. Create your feature branch (`git checkout -b feature/new-metric`).
3. Commit changes (`git commit -am 'Add new metric'`).
4. Push to the branch (`git push origin feature/new-metric`).
5. Submit a Pull Request detailing your changes.

## License

[Apache License 2.0](https://github.com/hgraph-io/hedera-stats/blob/main/LICENSE)
