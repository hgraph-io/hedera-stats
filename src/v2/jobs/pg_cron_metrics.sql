-----------------------------------
-- ECOSYSTEM METRICS (HEDERA STATS)
-- HGRAPH / www.hgraph.com
-----------------------------------

-- EVERY 1 MIN

select 
  cron.schedule_in_database(
    'call ecosystem.load_metrics_minute()', 
    -- every minute
    '* * * * *', 
    'call ecosystem.load_metrics_minute()', 
    '<database_name>', 
    '<database_user>'
  );

-- EVERY 1 HOUR

select 
  cron.schedule_in_database(
    'call ecosystem.load_metrics_hour()', 
    -- Hourly at minute 2
    '2 * * * *', 
    'call ecosystem.load_metrics_hour()', 
    '<database_name>', 
    '<database_user>'
  );

-- EVERY 1 DAY

select 
  cron.schedule_in_database(
    'call ecosystem.load_metrics_day()', 
    -- Daily at 12:05am
    '5 0 * * *', 
    'call ecosystem.load_metrics_day()', 
    '<database_name>', 
    '<database_user>'
  );

-- EVERY 1 WEEK

select 
  cron.schedule_in_database(
    'call ecosystem.load_metrics_week()', 
    -- Weekly on Sunday at 12:15am
    '15 0 * * 0', 
    'call ecosystem.load_metrics_week()', 
    '<database_name>', 
    '<database_user>'
  );

-- EVERY 1 MONTH

select 
  cron.schedule_in_database(
    'call ecosystem.load_metrics_month()', 
    -- Monthly at 12:30am, on the 1st
    '30 0 1 * *', 
    'call ecosystem.load_metrics_month()', 
    '<database_name>', 
    '<database_user>'
  );

-- EVERY 1 QUARTER

select 
  cron.schedule_in_database(
    'call ecosystem.load_metrics_quarter()', 
    -- Quarterly at 12:30am (1st of Jan, Apr, Jul, Oct)
    '30 0 1 1,4,7,10 *', 
    'call ecosystem.load_metrics_quarter()', 
    '<database_name>', 
    '<database_user>'
  );

-- EVERY 1 YEAR

select 
  cron.schedule_in_database(
    'call ecosystem.load_metrics_year()', 
    -- Yearly at 12:30am on January 1st
    '30 0 1 1 *', 
    'call ecosystem.load_metrics_year()', 
    '<database_name>', 
    '<database_user>'
  );
