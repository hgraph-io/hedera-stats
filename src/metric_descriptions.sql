insert into ecosystem.metric_description (name, description, methodology)
values

('active_developer_accounts', 'An active developer account is one that performs at least one creative or infrastructure-related action, such as deploying contracts or minting tokens, within a given period.', 'Counts unique accounts that executed at least one developer-related transaction (e.g., contract deployment or token creation) during the period.'),
    ('active_retail_accounts', 'Active retail accounts are a subset of active accounts that exclude smart contracts and accounts with developer-like transactions.', 'Determined by filtering out smart contract accounts and developer accounts from all active accounts, leaving only active non-developer accounts.'),
    ('active_smart_contracts', 'The number of unique smart contracts invoked at least once in a gas-consuming transaction within a given time period.', 'Counts unique smart contracts that were successfully invoked via a gas-consuming (state-changing) transaction at least once during the period.'),
    ('active_ecdsa_accounts', 'Counts unique accounts with ECDSA keys that pay for at least one transaction within a given timeframe.', 'Counts unique accounts with ECDSA keys (starting with 02 or 03) that initiated (paid for) at least one successful transaction in the period.'),
    ('active_ed25519_accounts', 'Counts unique ED25519 accounts that pay transaction fees within the chosen timeframe.', 'Counts unique accounts with ED25519 keys (public key prefix 0x1220) that initiated at least one successful transaction in the chosen timeframe.'),
    ('active_accounts', 'An active account is one that initiates at least one paid transaction within a given timeframe, showing direct engagement with the network.', 'Counts unique accounts that acted as the payer for at least one successful transaction in the given timeframe.'),
    ('network_fee', 'Calculates revenue by summing all transaction fees collected on the mainnet.', 'Sums all transaction fees charged during the period to compute the total network revenue from fees.'),
    ('network_tps', 'Measures the average number of transactions processed (per-second) by the Hedera network within a given period.', 'Divides the number of transactions in each time interval by the duration of that interval (in seconds) to obtain the average TPS, rounded down to a whole number.'),
    ('network_tvl', 'Total Value Locked (TVL) represents the total amount of assets locked within decentralized finance (DeFi) protocols on the Hedera network, as reported by DeFi Llama.', 'Uses data from the DeFiLlama API to record the total USD value locked in Hedera DeFi protocols each day.'),
    ('stablecoin_marketcap', 'Tracks the market capitalization of stablecoins circulating on the Hedera network as reported by DeFiLlama.', 'Fetches stablecoin circulation data from DeFiLlama and uses the peggedUSD value to record the stablecoin market cap (USD) for each day.'),
    ('avg_usd_conversion', 'Aggregates the latest price of HBAR from multiple sources, making it crucial for real-time tracking and analyzing price trends.', 'The average of candlestick closing prices for a given period for the HBAR/USDT pair on the five major exchanges by trading volume (Binance, Bybit, OKX, Bitget and MEXC) was calculated. The price is multiplied by 10,000 for integer representation for each time period.'),
    ('new_accounts', 'Tracks the number of Hedera accounts created within a specific time period.', 'Counts the number of accounts created within the specified time period based on their creation timestamps.'),
    ('new_ecdsa_accounts', 'Counts newly created Hedera accounts that use an ECDSA key during the selected period.', 'Filters account creation events during the period for those with ECDSA public keys (starting with 02 or 03) and counts them.'),
    ('new_ed25519_accounts', 'Counts new Hedera accounts that use an ED25519 key during the specified period.', 'Counts new accounts created in the period that use ED25519 keys (public key prefix 0x1220).'),
    ('new_smart_contracts', 'Counts contract entities created on Hedera during the chosen period.', 'Counts the number of smart contract creation events (successful CONTRACTCREATE transactions) that occurred during the given period.'),
    ('total_accounts', 'Reflects the cumulative number of Hedera accounts created since genesis.', 'Counts all accounts created since network inception up to the specified time, yielding the total number of Hedera accounts.'),
    ('total_ecdsa_accounts', 'Shows the cumulative number of Hedera accounts secured with ECDSA keys.', 'Counts all accounts with ECDSA public keys (prefix 02 or 03) created up to the given time, providing the total number of ECDSA-backed (key starting with 02 or 03) accounts.'),
    ('total_ed25519_accounts', 'Reports the total number of Hedera accounts that use ED25519 keys.', 'Counts all accounts with ED25519 keys (prefix 0x1220) created up to the specified time, yielding the total number of ED25519-backed (public key prefix 0x1220) accounts.'),
    ('total_smart_contracts', 'Represents the cumulative number of contract entities deployed on Hedera.', 'Counts all contract entities (type CONTRACT) created since genesis up to the specified time, providing the cumulative total of smart contracts deployed.'),
    -- LEGACY METRICS (pre-hedera stats)
    ('account_growth', 'The number of created accounts that do transactions but are not smart contracts or developers during the period', ''),
    ('total_nfts', 'Total number of NFTs in the ecosystem', ''),
    ('nft_holders', 'Total number of NFT holders in the ecosystem', ''),
    ('nft_market_cap', 'Total market capitalization of NFTs in the ecosystem', ''),
    ('nft_holders_per_period', 'Number of NFT holders during the period', ''),
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
    ('nft_sales_volume', 'Volume of NFT sales during the period', '')
on conflict (name) do update
set
    description = excluded.description,
    methodology = excluded.methodology;
    