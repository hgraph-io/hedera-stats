-- hourly job
select cron.schedule_in_database(
    'call ecosystem.load_hourly_metrics()',
    -- hourly at minute 3
    '3 * * * *',
    'call ecosystem.load_hourly_metrics();',
    '<database_name>',
    '<database_user>'
);

-- daily job
select cron.schedule_in_database(
    'call ecosystem.load_metrics()',
    -- daily at midnight
    '0 0 * * *',
    'call ecosystem.load_metrics();',
    '<database_name>',
    '<database_user>'
);

-- daily job
select cron.schedule_in_database(
    'call ecosystem.load_network_tvl()',
    -- daily after midnight UTC
    '2 * * * *',
    'call ecosystem.load_network_tvl();',
    '<database_name>',
    '<database_user>'
);

-- daily job
select cron.schedule_in_database(
    'call ecosystem.load_stablecoin_marketcap()',
    -- daily after midnight UTC
    '3 * * * *',
    'call ecosystem.load_stablecoin_marketcap()',
    '<database_name>',
    '<database_user>'
);

-- daily job
select cron.schedule_in_database(
    'refresh materialized concurrently view ecosystem.hashgraph_dashboard',
    -- daily after midnight UTC
    '10 * * * *',
    'refresh materialized view concurrently ecosystem.hashgraph_dashboard',
    '<database_name>',
    '<database_user>'
);
