# Changelog

All notable changes to the Hedera Stats project since August 1, 2024.

## [Unreleased] - 2025-09-29

### Added

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
