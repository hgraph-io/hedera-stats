------------------------------------------
-- HGRAPH ECOSYSTEM METRICS (HEDERA STATS)
-- DOCS / docs.hgraph.com/hedera-stats
------------------------------------------

-- Replace <database_name> with "hedera_mainnet" or "hedera_testnet"


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
    -- Daily at 12:02am
    '2 0 * * *', 
    'call ecosystem.load_metrics_day()', 
    '<database_name>'
  );

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_beta', 
    -- Daily at 12:03am
    '3 0 * * *', 
    'call ecosystem.load_metrics_beta()', 
    '<database_name>'
  );


-- EVERY 1 WEEK

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_week', 
    -- Weekly on Sunday at 12:02am
    '2 0 * * 0', 
    'call ecosystem.load_metrics_week()', 
    '<database_name>'
  );


-- EVERY 1 MONTH

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_month', 
    -- Monthly at 12:04am, on the 1st
    '4 0 1 * *', 
    'call ecosystem.load_metrics_month()', 
    '<database_name>'
  );


-- EVERY 1 QUARTER

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_quarter', 
    -- Quarterly at 12:08am (1st of Jan, Apr, Jul, Oct)
    '8 0 1 1,4,7,10 *', 
    'call ecosystem.load_metrics_quarter()', 
    '<database_name>'
  );


-- EVERY 1 YEAR

SELECT 
  cron.schedule_in_database(
    'ecosystem_load_metrics_year', 
    -- Yearly at 12:14am on January 1st
    '14 0 1 1 *', 
    'call ecosystem.load_metrics_year()', 
    '<database_name>'
  );
