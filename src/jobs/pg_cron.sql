--------------------------------
-- every 5 minutes
--------------------------------
select cron.schedule_in_database(
    'refresh materialized view concurrently transactions_last_24hrs',
    '*/5 * * * *',
    'refresh materialized view concurrently transactions_last_24hrs;',
    '<database_name>',
    '<database_user>'
);

select cron.schedule_in_database(
    'refresh materialized view concurrently total_accounts',
    '*/5 * * * *',
    'refresh materialized view concurrently total_accounts;',
    '<database_name>',
    '<database_user>'
);

select cron.schedule_in_database(
    'refresh materialized view concurrently contract_transactions_last_24hrs',
    '1-59/5 * * * *',
    'refresh materialized view concurrently contract_transactions_last_24hrs;',
    '<database_name>',
    '<database_user>'
);
--------------------------------
-- hourly
--------------------------------
select cron.schedule_in_database(
    'call ecosystem.load_transaction_metrics()',
    -- hourly at minute 1
    '1 * * * *',
    'call ecosystem.load_transaction_metrics();',
    '<database_name>',
    '<database_user>'
);


select cron.schedule_in_database(
    'call ecosystem.load_fees_by_transaction_type()',
    -- hourly at minute 1
    '1 * * * *',
    'call ecosystem.load_fees_by_transaction_type();',
    '<database_name>',
    '<database_user>'
);

select cron.schedule_in_database(
    'call ecosystem.load_network_deposits()',
    -- every hour at minute 1
    '1 * * * *',
    'call ecosystem.load_network_deposits();',
    '<database_name>',
    '<database_user>'
);


select cron.schedule_in_database(
    'call ecosystem.load_hourly_metrics()',
    -- hourly at minute 3
    '3 * * * *',
    'call ecosystem.load_hourly_metrics();',
    '<database_name>',
    '<database_user>'
);
--------------------------------
-- daily
--------------------------------
select cron.schedule_in_database(
    'call ecosystem.load_metrics()',
    -- daily at midnight
    '0 0 * * *',
    'call ecosystem.load_metrics();',
    '<database_name>',
    '<database_user>'
);

select cron.schedule_in_database(
    'call ecosystem.load_network_tvl()',
    -- daily after midnight UTC
    '2 0 * * *',
    'call ecosystem.load_network_tvl();',
    '<database_name>',
    '<database_user>'
);

select cron.schedule_in_database(
    'call ecosystem.load_stablecoin_marketcap()',
    -- daily after midnight UTC
    '3 0 * * *',
    'call ecosystem.load_stablecoin_marketcap()',
    '<database_name>',
    '<database_user>'
);

select cron.schedule_in_database(
    'refresh materialized concurrently view ecosystem.hashgraph_dashboard',
    -- daily after midnight UTC
    '10 0 * * *',
    'refresh materialized view concurrently ecosystem.hashgraph_dashboard',
    '<database_name>',
    '<database_user>'
);

--------------------------------
-- weekly
--------------------------------
select cron.schedule_in_database(
    'refresh materialized view concurrently ecosystem.active_nft_account_cohorts',
    -- weekly on Sunday at midnight
    '0 0 * * 0',
    'refresh materialized view concurrently ecosystem.active_nft_account_cohorts;',
    '<database_name>',
    '<database_user>'
);

