------------------------------------------
-- HGRAPH ECOSYSTEM METRICS (HEDERA STATS)
-- DOCS / docs.hgraph.com/hedera-stats
------------------------------------------

-- Replace <database_name> with "hedera_mainnet" or "hedera_testnet"

-- EVERY 1 MINUTE 

SELECT
  cron.schedule_in_database(
    'ecosystem_load_metrics_minute',
    '* * * * *',                             -- every minute
    'call ecosystem.load_metrics_minute()',
    '<database_name>'
  );

-- EVERY 10 MINUTES

-- Replace <tvl_minutes>/<marketcap_minutes> with the row for this instance:
--   hedera_mainnet   2-59/10   3-59/10
--   hedera_testnet   7-59/10   8-59/10
-- The two networks are deliberately offset. Both fetch the same mainnet-wide
-- DeFiLlama figures, so running them on the same minute makes both pay the same
-- CDN cache miss; offset, whichever runs first warms the cache for the other.
--
-- The jobname must stay equal to the command: these two were created with the
-- two-argument cron.schedule() on the publisher, which sets jobname = command.
-- pg_cron upserts by jobname, so renaming them here creates a SECOND job and
-- doubles the fetch rate instead of updating the existing one.

SELECT
  cron.schedule_in_database(
    'call ecosystem.load_network_tvl()',
    '<tvl_minutes> * * * *',
    'call ecosystem.load_network_tvl()',
    '<database_name>'
  );

SELECT
  cron.schedule_in_database(
    'call ecosystem.load_stablecoin_marketcap()',
    '<marketcap_minutes> * * * *',
    'call ecosystem.load_stablecoin_marketcap()',
    '<database_name>'
  );


-- EVERY 1 HOUR

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_hour', 
    -- Hourly at minute 1
    '1 * * * *', 
    'call ecosystem.load_metrics_hour()', 
    '<database_name>'
  );


-- EVERY 1 DAY

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_day', 
    -- Daily at 12:02am UTC
    '2 0 * * *', 
    'call ecosystem.load_metrics_day()', 
    '<database_name>'
  );

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_beta', 
    -- Daily at 12:03am UTC
    '3 0 * * *', 
    'call ecosystem.load_metrics_beta()', 
    '<database_name>'
  );


-- EVERY 1 WEEK

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_week', 
    -- Weekly on Sunday at 12:02am UTC
    '2 0 * * 0', 
    'call ecosystem.load_metrics_week()', 
    '<database_name>'
  );


-- EVERY 1 MONTH

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_month', 
    -- Monthly at 12:04am UTC, on the 1st
    '4 0 1 * *', 
    'call ecosystem.load_metrics_month()', 
    '<database_name>'
  );


-- EVERY 1 QUARTER

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_quarter', 
    -- Quarterly at 12:08am UTC (1st of Jan, Apr, Jul, Oct)
    '8 0 1 1,4,7,10 *', 
    'call ecosystem.load_metrics_quarter()', 
    '<database_name>'
  );


-- EVERY 1 YEAR

SELECT
  cron.schedule_in_database(
    'ecosystem_load_metrics_year',
    -- Yearly at 12:14am UTC on January 1st
    '14 0 1 1 *',
    'call ecosystem.load_metrics_year()',
    '<database_name>'
  );
