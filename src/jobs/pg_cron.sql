-- hourly job
select cron.schedule_in_database(
    'call ecosystem.load_hourly_metrics()',
    -- hourly at minute 3
    '3 * * * *',
    'call ecosystem.load_hourly_metrics();',
    'hedera_testnet',
    'hedera_testnet_owner'
    -- 'hedera_mainnet',
    -- 'hedera_mainnet_owner'
);

-- daily job
select cron.schedule_in_database(
    'call ecosystem.load_metrics()',
    -- daily at midnight
    '0 0 * * *',
    'call ecosystem.load_metrics();',
    'hedera_testnet',
    'hedera_testnet_owner'
    /* 'hedera_mainnet', */
    /* 'hedera_mainnet_owner' */
);
