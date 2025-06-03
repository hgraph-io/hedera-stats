insert into ecosystem.metric_description (name, description, methodology)
values
    ('accounts_associating_nfts', 'Number of accounts that associated NFTs during the period', ''),
    ('accounts_receiving_nfts', 'Number of accounts that received NFTs during the period', ''),
    ('accounts_sending_nfts', 'Number of accounts that sent NFTs during the period', ''),
    ('accounts_minting_nfts', 'Number of accounts that minted NFTs during the period', ''),
    ('accounts_creating_nft_collections', 'Number of accounts that created NFT collections during the period', ''),
    ('active_nft_accounts', 'Number of active NFT accounts during the period', ''),
    ('active_nft_builder_accounts', 'Number of active NFT builder accounts during the period', ''),
    ('nft_collections_created', 'Number of NFT collections created during the period', ''),
    ('nfts_minted', 'Number of NFTs minted during the period', ''),
    ('nfts_transferred', 'Number of NFTs transferred during the period', ''),
    ('nft_sales_volume', 'Volume of NFT sales during the period', ''),
    ('active_developer_accounts', 'Developer across the different Hedera services, measured by the number of unique accounts that submit these creative transaction types during the period.', ''),
    ('active_retail_accounts', 'Accounts that do transactions but are not smart contracts or developers during the period', ''),
    ('active_smart_contracts', 'The number of unique smart contracts that have had activity during the period', ''),
    ('active_accounts', 'The number equal developers + retails + smart contracts during the period', ''),
    ('network_fee', 'The total network fee for the period during the period', ''),
    ('account_growth', 'The number of created accounts that do transactions but are not smart contracts or developers during the period', ''),
    ('network_tps', 'The number of transactions per second during the period', ''),
    ('total_nfts', 'Total number of NFTs in the ecosystem', ''),
    ('nft_holders', 'Total number of NFT holders in the ecosystem', ''),
    ('nft_market_cap', 'Total market capitalization of NFTs in the ecosystem', ''),
    ('nft_holders_per_period', 'Number of NFT holders during the period', ''),
    ('network_tvl', 'Total value locked (USD) in the ecosystem during the period', ''),
    ('stablecoin_marketcap', 'Total market capitalization (USD) of stablecoins in the ecosystem during the period', ''),
    ('avg_usd_conversion', 'Average conversion of HBAR to US dollars multiplied by 10,000 during the period', 'The average of candlestick closing prices for a given period for the HBAR/USDT pair on the five major exchanges by trading volume (Binance, Bybit, OKX, Bitget and MEXC) was calculated. The price is multiplied by 10,000 for integer representation for each time period.'),
    ('new_accounts', 'New accounts created on the Hedera network per period', '')
on conflict (name) do update
set
    description = excluded.description,
    methodology = excluded.methodology;
