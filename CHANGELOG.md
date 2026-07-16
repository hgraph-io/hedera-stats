# Changelog

All notable changes to the Hedera Stats project since August 1, 2024.

## [Unreleased] - 2026-04-22

### Added

- Migrated the tracked legacy `ecosystem` objects into this repo as migrations `071`–`082`: the `transaction_count_by_type` table + `transactions_by_type`, and the per-period query functions (`transactions_per_period`, `associated_transactions_per_period`, `transaction_fees_per_period`, `associated_transaction_fees_per_period`, `fungible_token_transfers_per_period`, `non_fungible_token_transfers_per_period`, `smart_contract_calls_per_period`, `hcs_messages_per_period`, `active_accounts_per_period`, `nft_holders_per_period`). These are exposed via Hasura, so the subscriber needs them; the `transaction_count_by_type` table also lets the schema-wide `ecosystem_pub` publication replicate without erroring. Fixed the eight `*_per_period` functions that emitted a stray `description` column (`ecosystem.metric` has only name/period/timestamp_range/total) — they were return-type-mismatched against the current 4-column metric
- `total_erc20_accounts` metric: rolling total of unique EVM addresses that have received ERC-20 tokens, sourced from the erc indexer's `token_transfer` table; added to day, week, and month load procedures
- `total_erc721_accounts` metric: rolling total of unique accounts holding an ERC-721 token with a positive balance, sourced from the erc indexer's `token_account` table (contract_type `ERC_721`); added to day, week, and month load procedures
- `total_erc1400_accounts` metric: rolling total of unique accounts holding an ERC-1400 token with a positive balance, sourced from the erc indexer's `token_account` table (contract_type `ERC_1400`); added to day, week, and month load procedures
- `total_erc3643_accounts` metric: rolling total of unique accounts holding an ERC-3643 (T-REX) token with a positive balance, sourced from the erc indexer's `token_account` table (contract_type `ERC_3643`); added to day, week, and month load procedures. Returns an empty set until ERC-3643 tokens are deployed on Hedera
- One-shot Docker migration runner: a slim `psql`+`bash` image (`Dockerfile`) whose `CMD` runs `migrate.sh`, with per-network services in `docker-compose.yml` (`docker compose run --rm mainnet|testnet`). It applies pending migrations and exits — no long-running container or Postgres server in this repo
- Migrations create objects only in the `ecosystem` schema, never in `public`. The mirror-node enum/domain types and replicated tables in `public`, and the `timestamp9`/`http` extensions, are external prerequisites (the mirror node / a superuser provides them); the `ecosystem_owner` role has no rights on `public`
- `top_fungible_tokens_hts` metric (HBAR & DeFi): on-demand ranking of top HTS fungible tokens by a composite score (40% market cap + 40% DEX volume + 20% transactions), each component log-normalized then min-max scaled over a rolling window (default 24h). Phase 1 is on-demand only (no persistence or scheduled jobs)
- `top_fungible_tokens_erc` metric (HBAR & DeFi): on-demand ranking of top ERC-20 fungible tokens by a composite score (60% transactions + 40% unique holders), each min-max scaled over a rolling window (default 720h / 30d). Activity-based rather than value-based: ERC-20 tokens on Hedera have no USD price source (per HG-2955) and their transfers do not settle in HBAR, so no market-cap or volume axis is possible. Sourced from the erc indexer's `token_transfer` table (contract_type `ERC_20`). Phase 1 is on-demand only (no persistence or scheduled jobs)

### Changed

- `top_non_fungible_tokens_erc` metric (Non-Fungible Tokens): validated and productionized the previously dead ERC-721 ranking. Fixed sales-volume attribution (the prior filter keyed on `sender_account_id`, which is NULL for pure-EVM transfers, silently zeroing all volume); volume is now the sum of positive `crypto_transfer` legs credited to non-system accounts (`entity_id > 1000`), computed once per transaction to avoid `nft_transfer`×`crypto_transfer` fan-out. Default window widened from 72h to 720h (30d) since ERC-721 sales are sparse. Return type changed from a composite TYPE to a real tracking TABLE so Hasura can track the function for GraphQL exposure (mirrors `top_fungible_tokens_hts`). On-demand only (no persistence or scheduled jobs)
- Stats computation now runs in its own Postgres container instead of on the mirror node
- The stats DB is a Postgres **logical replication subscriber** to the mirror node (publisher): mirror-node tables are replicated in as local tables. The subscription and the local schema it replicates into are provisioned outside this repo; the container assumes those tables are present when metric migrations run
- No longer requires superuser or extension-installation access on the mirror node database
- Migration-based bring-up: `src/migrations/` is now the sole apply path. `001-init.sql` holds the schema skeleton (folding in the `metric_description` table and `metric_start_date`/`metric_end_date` helpers the init script used to create inline), and every metric function, the descriptions, the seed, and each load procedure is its own dependency-ordered `NNN-name.sql`. Replaces the duplicated `src/up.sql` and orphaned `src/metrics/setup/up.sql` and the bulk-loading of `src/metrics`/`src/jobs` by the init script
- Migrations apply with `check_function_bodies` on, so baseline migrations are ordered by inter-function dependency (a function's migration follows the migrations defining the `ecosystem.*` functions it calls)
- Tracked migration runner (`src/migrations/migrate.sh`) with an `ecosystem.schema_migrations` table: applies unapplied `NNN-*.sql` once each, in filename order; safe to re-run (applied versions skipped). Connects over the Unix socket via libpq `PG*` env vars (`PGHOST` defaults to `/var/run/postgresql`); credential-free via peer auth. `PGOPTIONS` sets the owning role per network
- `src/metrics/`, `src/metric_descriptions.sql`, and `src/jobs/*.sql` are retained as the readable source the baseline migrations were generated from; they are no longer loaded at runtime
- Per-network one-shot services (`mainnet`, `testnet`) in `docker-compose.yml` that deploy the migrations into a co-located network mirror-node database. Bind-mount the host Postgres socket and run as the host postgres UID (peer auth, no password), owning objects as the per-network `hedera_<net>_ecosystem_owner` group role via `PGOPTIONS`. mainnet → 5433 / `hedera_mainnet`; testnet → 5432 / `hedera_testnet`. Requires (external, superuser) the `timestamp9` and `http` extensions and `CREATE` on the database for the ecosystem_owner role. Set `POSTGRES_UID` if the host postgres user isn't UID 999

### Removed

- `src/up.sql` and `src/metrics/setup/up.sql` — superseded by `src/migrations/001-init.sql`
- The long-running Postgres container and its init scripts (`docker/postgres/`, the `01-init.sh` wrapper, `00-mirror-node-types.sql`) and the host `deploy.sh` wrapper. Bring-up is now migrations-only via the one-shot runner: the schema skeleton lives in `001-init.sql`. Extension and mirror-node-type creation were removed entirely — the extensions and everything in `public` are external prerequisites (the migrations are pure `ecosystem`-schema SQL)
- pg_cron setup from the subscriber (no `pg_cron` extension or `pg_cron_metrics.sql` applied at bring-up). Cron drives metric loading and belongs on the publisher; `src/jobs/pg_cron_metrics.sql` is kept for that purpose
- `postgres_fdw` and all foreign-table setup (`CREATE SERVER`, user mapping, `IMPORT FOREIGN SCHEMA`). Mirror-node tables now arrive via logical replication instead of foreign tables

## [2025-09-29]

### Added

- NFT collections created metric upgraded from legacy to active with proper methodology, added to all load procedures (hour, day, week, month, quarter, year)
- Average network fee metric (avg_network_fee) to calculate mean transaction fee cost per period
- Average gas used metrics: avg_gas_used (all types), avg_gas_used_contract_call, avg_gas_used_ethereum_tx, avg_gas_used_contract_create
- Daily period support for avg_time_to_consensus metric with automated ETL pipeline
- Minute period support for avg_usd_conversion metric with 72-hour retention
- Load metrics minute procedure for high-frequency price updates
- Init script for backfilling minute-level price data
- HBAR market cap metric that calculates market capitalization by multiplying price by circulating supply (#59)
- HBAR total supply metric (50 billion constant) in hbar-defi category
- ECDSA accounts with real EVM addresses metric (#51)
- New folder structure for better organization (#52)
- Transaction metrics with simplified categorization (#47)
- Total ECDSA accounts metric functions
- New initialization functions for metrics
- Hourly support for hbar_total_released and hbar_market_cap metrics

### Changed

- Removed Bybit from avg_usd_conversion exchange sources (now uses 4 exchanges: Binance, OKX, Bitget, MEXC)
- Updated metric descriptions
- Refactored transaction metrics to use simplified HCS and total categories
- Updated job procedures for better metric loading
- Reorganized folder structure for metrics

### Fixed

- SQL parameter references in NFT sales functions (#50)
- Initialize procedures for proper metric loading

## [2025-08-01 to 2025-08-14]

### Added

- **Transaction Metrics** - New comprehensive transaction categorization system
- **ECDSA Account Metrics** - Functions to track ECDSA accounts with real EVM addresses
- **NFT Collection Sales** - Enhanced NFT sales volume tracking functions (#48, #49)
- **Workflow Documentation** - Added WORKFLOW.md file for development guidance (#43)
- **Claude.md** - AI assistant instructions for better code generation

### Changed

- Simplified transaction metrics to HCS and total categories
- Renamed metric columns from various names to standardized "total"
- Moved deprecated files to new structure (#44)
- Updated README with pg_http requirements and pg_cron placeholders
- Optimized metric loader procedures (#45)

### Fixed

- NFT sales SQL parameter references and comment cleanup
- Fixed typo in SQL extension creation command
- Metric loader initialization issues

## [2025-07-01 to 2025-07-31]

### Added

- New metric calculation functions for various network statistics
- Metric loader procedures for automated data processing
- Initial v2 architecture implementation (#37)

### Changed

- Updated metric procedures and cron job configurations
- Reorganized file structure for better maintainability
- Enhanced SQL formatting across all metric functions

### Fixed

- Year job period comment in constants
- Various SQL function optimizations

## [2025-06-01 to 2025-06-30]

### Added

- Init metrics for bootstrapping historical data (#33)
- Total metrics aggregation functions (#31)
- New active ED/EC account metrics
- Enhanced account cohort tracking

### Changed

- Optimized ordering of procedure metrics text array (#35)
- Updated active accounts function for better performance (#34)
- Refactored stats system for improved reliability

### Fixed

- Prevented partial data loading in metrics (#36)
- Fixed new accounts SQL query issues
- Applied fixes to total accounts metrics

## [2025-05-01 to 2025-05-31]

### Added

- Metric descriptions moved to dedicated file (#26)
- New accounts metrics with enhanced tracking
- Daily metrics for key performance indicators (#23)

### Changed

- Increased DeFi Llama ingestion frequency (#27)
- Aligned DeFiLlama metrics with UTC day boundaries (#24)

### Fixed

- Stats redundancy improvements (#22)

## [2025-04-01 to 2025-04-30]

### Added

- Period parameter back to active_nft_account_cohorts (#21)
- Updated Grafana dashboard JSON configuration (#20)

### Changed

- Updated license information in README (#19)
- Fixed documentation links (#18)

## [2025-03-01 to 2025-03-31]

### Added

- 1-year change metrics to Grafana dashboard (#17)
- Additional scheduled jobs (#15)
- Comments and documentation improvements (#14)
- Previous year metrics for historical comparisons (#12)

### Changed

- Refresh materialized views concurrently for better performance
- Script to backload avg_usd_conversion data

### Fixed

- Removed null entries from ecosystem metrics (#11)
- Corrected days-in-year calculation (#13)
- Updated older metrics for consistency

## [2025-02-01 to 2025-02-29]

### Added

- Grafana dashboard JSON export functionality (#5)
- Dashboard-specific revenue metrics
- KPI dashboard updates
- Time to consensus ETL pipeline (#1, #2)
- Scheduled job for avg_time_to_consensus metrics

### Changed

- Refactored network_tvl to not calculate averages
- Optimized SELECT DISTINCT queries
- Simplified retail account calculations

### Fixed

- Long-running load_hourly_metrics() job performance (#8)
- Success requirement for charged transaction fees
- Materialized view refresh with proper indexing
- Timestamp range handling for single-row results (#9, #10)

## [2025-01-14 to 2025-01-31]

### Added

- ETL pipeline for average time to consensus metrics
- Initial repository setup and core infrastructure

### Infrastructure

- PostgreSQL-based metrics calculation system
- pg_cron integration for scheduled jobs
- Grafana dashboard configurations
- Mirror node data integration

## Project Foundation

The project established a comprehensive metrics platform for the Hedera network with:

- SQL-based metric calculation functions
- Automated job scheduling via pg_cron
- Grafana visualization dashboards
- Time-series data storage in ecosystem.metric table
- Support for multiple time ranges (hour, day, week, month, quarter, year)
- Network-specific metrics (mainnet, testnet)
