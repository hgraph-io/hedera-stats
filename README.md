# Hedera Stats: Shared Ecosystem and Network Insights

**[Hedera Stats](https://docs.hgraph.com/hedera-stats/introduction)** provides quantitative statistical measurements for the Hedera network, leveraging open-source methodologies, Hedera mirror node data, third-party data sources, and Hgraph's GraphQL API. These statistics include network performance metrics, NFT analytics, account activities, and economic indicators, enabling transparent and consistent analysis of the Hedera ecosystem.

**[📖 View Full Documentation →](https://docs.hgraph.com/category/hedera-stats)**

## Getting Started

### Prerequisites
- **Hedera Mirror Node** or access to **Hgraph's GraphQL API**
  - [Create a free account](https://hgraph.com/hedera)
- **Prometheus** (`promtool`) for `avg_time_to_consensus` ([view docs](https://prometheus.io/docs/introduction/overview/))
- **PostgreSQL database** needed for SQL script execution ([view docs](https://www.postgresql.org/docs/current/))
- **DeFiLlama API** for decentralized finance metrics ([view docs](https://defillama.com/docs/api)).

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
- Execute `src/up.sql` to create necessary database schema and tables.
- Load initial data using SQL scripts from the `src/jobs` directory.

Configure environment variables (example `.env`):

```env
DATABASE_URL="postgresql://user:password@localhost:5432/hedera_stats"
HGRAPH_API_KEY="your_api_key"
```

Schedule incremental updates:

```bash
crontab -e
1 * * * * cd /path/to/hedera-stats/src/time-to-consensus && bash ./run.sh >> ./.raw/cron.log 2>&1
```

## Repository Structure
```
hedera-stats/
├── src/
│   ├── dashboard/             # SQL for Grafana dashboards & Grafana template
│   ├── helpers/               # Helper SQL functions
│   ├── jobs/                  # Incremental data update scripts
│   ├── metrics/               # SQL queries for metrics
│   └── up.sql                 # Initial database schema setup
├── LICENSE
└── README.md
```

## Available Metrics & Usage

Metrics categories include:

- Accounts & Network Participants
- NFT-specific Metrics
- Network Performance & Economic Metrics

[**View all metrics & documentation →**](https://docs.hgraph.com/category/hedera-stats)

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

### Improve query performance:
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

TBD