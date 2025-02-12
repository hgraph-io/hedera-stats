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

select cron.schedule_in_database(
    'call ecosystem.load_stablecoin_marketcap()',
    -- daily after midnight UTC
    '3 * * * *',
    'call ecosystem.load_stablecoin_marketcap()',
    '<database_name>',
    '<database_user>'
);
