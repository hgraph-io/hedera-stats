insert into ecosystem.metric_description (name, description, methodology)
values
    -- HBAR & DeFi
    ('hbar_total_supply', 'The total supply of HBAR tokens pre-minted at network genesis (50 billion HBAR).', 'Fixed supply of 50 billion HBAR (5,000,000,000,000,000,000 tinybars) as defined in the Hedera protocol. This value is hardcoded in the Mirror Node and cannot change without unanimous consent of the Hedera Council. Note: Summing all entity balances yields 49,999,943,600 HBAR due to 56,400 HBAR existing at protocol level outside any account.'),
    ('hbar_total_released', 'The circulating (released) supply of HBAR tokens in tinybars, representing the amount available for use in the ecosystem.', 'Calculates released supply using a calibration constant (351,871,530,222,399,283 tinybars) minus cumulative net flows from 548 designated treasury/system accounts since Sept 13, 2019 22:00 UTC (when mirror node data begins). The calibration constant accounts for ~3.52B HBAR distributed before mirror node data collection. Treasury accounts include: 0.0.2 (primary treasury), 0.0.42, 0.0.44-71, 0.0.73-87, 0.0.99-100, 0.0.200-349, and 0.0.400-750. Negative flows from these accounts represent HBAR releases into circulation. Returns value in tinybars.'),
    ('avg_usd_conversion', 'Aggregates the latest price of HBAR from multiple sources, making it crucial for real-time tracking and analyzing price trends.', 'The average of candlestick closing prices for a given period for the HBAR/USDT pair on the five major exchanges by trading volume (Binance, Bybit, OKX, Bitget and MEXC) was calculated. The price is multiplied by 100,000 for integer representation for each time period.'),
    ('hbar_market_cap', 'Market capitalization of HBAR tokens in USD cents, calculated by multiplying price by circulating supply.', 'Multiplies avg_usd_conversion (price × 100,000) by hbar_total_released (supply in tinybars). Formula: (price_x100000 × supply_tinybars) / 100,000,000,000. Stored as cents (×100) for precision. To display in USD, divide by 100.'),
    ('network_tvl', 'Total Value Locked (TVL) represents the total amount of assets locked within decentralized finance (DeFi) protocols on the Hedera network, as reported by DeFi Llama.', 'Uses data from the DeFiLlama API to record the total USD value locked in Hedera DeFi protocols each day.'),
    ('stablecoin_marketcap', 'Tracks the market capitalization of stablecoins circulating on the Hedera network as reported by DeFiLlama.', 'Fetches stablecoin circulation data from DeFiLlama and uses the peggedUSD value to record the stablecoin market cap (USD) for each day.'),
    -- Network Performance
    ('network_fee', 'Calculates revenue by summing all transaction fees collected on the mainnet.', 'Sums all transaction fees charged during the period to compute the total network revenue from fees.'),
    ('avg_time_to_consensus', 'Measures the average time it takes for transactions to reach consensus on the Hedera network within a given period.', 'Calculates the average difference between transaction submission time and consensus timestamp for all transactions in the period.'),
    ('network_tps', 'Measures the average number of transactions processed (per-second) by the Hedera network within a given period.', 'Divides the number of transactions in each time interval by the duration of that interval (in seconds) to obtain the average TPS, rounded down to a whole number.'),
    -- Activity & Engagement - Active Accounts
    ('active_accounts', 'An active account is one that initiates at least one paid transaction within a given timeframe, showing direct engagement with the network.', 'Counts unique accounts that acted as the payer for at least one successful transaction in the given timeframe.'),
    ('active_developer_accounts', 'An active developer account is one that performs at least one creative or infrastructure-related action, such as deploying contracts or minting tokens, within a given period.', 'Counts unique accounts that executed at least one developer-related transaction (e.g., contract deployment or token creation) during the period.'),
    ('active_retail_accounts', 'Active retail accounts are a subset of active accounts that exclude smart contracts and accounts with developer-like transactions.', 'Determined by filtering out smart contract accounts and developer accounts from all active accounts, leaving only active non-developer accounts.'),
    ('active_ecdsa_accounts', 'Counts unique accounts with ECDSA keys that pay for at least one transaction within a given timeframe.', 'Counts unique accounts with ECDSA keys (starting with 02 or 03) that initiated (paid for) at least one successful transaction in the period.'),
    ('active_ed25519_accounts', 'Counts unique ED25519 accounts that pay transaction fees within the chosen timeframe.', 'Counts unique accounts with ED25519 keys (public key prefix 0x1220) that initiated at least one successful transaction in the chosen timeframe.'),
    -- Activity & Engagement - New Accounts
    ('new_accounts', 'Tracks the number of Hedera accounts created within a specific time period.', 'Counts the number of accounts created within the specified time period based on their creation timestamps.'),
    ('new_ecdsa_accounts', 'Counts newly created Hedera accounts that use an ECDSA key during the selected period.', 'Filters account creation events during the period for those with ECDSA public keys (starting with 02 or 03) and counts them.'),
    ('new_ecdsa_accounts_real_evm', 'Counts newly created ECDSA accounts that have real EVM addresses (not hollow accounts) during the selected period.', 'Filters new ECDSA accounts created in the period for those with actual EVM address associations, excluding hollow accounts.'),
    ('new_ed25519_accounts', 'Counts new Hedera accounts that use an ED25519 key during the specified period.', 'Counts new accounts created in the period that use ED25519 keys (public key prefix 0x1220).'),
    -- Activity & Engagement - Total Accounts
    ('total_accounts', 'Reflects the cumulative number of Hedera accounts created since genesis.', 'Counts all accounts created since network inception up to the specified time, yielding the total number of Hedera accounts.'),
    ('total_ecdsa_accounts', 'Shows the cumulative number of Hedera accounts secured with ECDSA keys.', 'Counts all accounts with ECDSA public keys (prefix 02 or 03) created up to the given time, providing the total number of ECDSA-backed (key starting with 02 or 03) accounts.'),
    ('total_ecdsa_accounts_real_evm', 'Shows the cumulative number of ECDSA accounts with real EVM addresses on Hedera.', 'Counts all ECDSA accounts with real EVM address associations created up to the given time, excluding hollow accounts.'),
    ('total_ed25519_accounts', 'Reports the total number of Hedera accounts that use ED25519 keys.', 'Counts all accounts with ED25519 keys (prefix 0x1220) created up to the specified time, yielding the total number of ED25519-backed (public key prefix 0x1220) accounts.'),
    -- Transactions - New
    ('new_transactions', 'Tracks the number of new transactions processed on the Hedera network within a specific time period.', 'Counts all successful transactions that occurred during the specified time period.'),
    ('new_crypto_transactions', 'Counts new cryptocurrency-related transactions (transfers, account updates) within the period.', 'Filters and counts transactions of crypto types (CRYPTOTRANSFER, CRYPTOCREATEACCOUNT, etc.) during the period.'),
    ('new_hcs_transactions', 'Counts new Hedera Consensus Service message submissions within the period.', 'Counts CONSENSUSSUBMITMESSAGE and related HCS transaction types during the specified period.'),
    ('new_hfs_transactions', 'Counts new Hedera File Service transactions within the period.', 'Counts FILECREATE, FILEUPDATE, FILEDELETE and other HFS transaction types during the period.'),
    ('new_hscs_transactions', 'Counts new Hedera Smart Contract Service transactions within the period.', 'Counts CONTRACTCALL, CONTRACTCREATE and other smart contract transaction types during the period.'),
    ('new_hts_transactions', 'Counts new Hedera Token Service transactions within the period.', 'Counts TOKENCREATION, TOKENMINT, TOKENBURN and other HTS transaction types during the period.'),
    ('new_other_transactions', 'Counts miscellaneous transaction types not categorized in main service groups within the period.', 'Counts transactions that do not fall into crypto, HCS, HFS, HSCS, or HTS categories during the period.'),
    -- Transactions - Total
    ('total_transactions', 'Represents the cumulative number of all transactions processed on Hedera since genesis.', 'Counts all successful transactions from network inception up to the specified time.'),
    ('total_crypto_transactions', 'Shows the cumulative number of cryptocurrency-related transactions on Hedera.', 'Counts all crypto-type transactions from genesis up to the specified time.'),
    ('total_hcs_transactions', 'Reports the total number of Hedera Consensus Service transactions since genesis.', 'Counts all HCS transaction types from network inception up to the specified time.'),
    ('total_hfs_transactions', 'Displays the cumulative number of Hedera File Service transactions.', 'Counts all HFS transaction types from genesis up to the specified time.'),
    ('total_hscs_transactions', 'Shows the total number of Hedera Smart Contract Service transactions.', 'Counts all smart contract transaction types from network inception up to the specified time.'),
    ('total_hts_transactions', 'Represents the cumulative number of Hedera Token Service transactions.', 'Counts all HTS transaction types from genesis up to the specified time.'),
    ('total_other_transactions', 'Reports the total number of miscellaneous transactions not in main categories.', 'Counts all other transaction types from network inception up to the specified time.'),
    -- EVM
    ('active_smart_contracts', 'The number of unique smart contracts invoked at least once in a gas-consuming transaction within a given time period.', 'Counts unique smart contracts that were successfully invoked via a gas-consuming (state-changing) transaction at least once during the period.'),
    ('new_smart_contracts', 'Counts contract entities created on Hedera during the chosen period.', 'Counts the number of smart contract creation events (successful CONTRACTCREATE transactions) that occurred during the given period.'),
    ('total_smart_contracts', 'Represents the cumulative number of contract entities deployed on Hedera.', 'Counts all contract entities (type CONTRACT) created since genesis up to the specified time, providing the cumulative total of smart contracts deployed.'),
    -- NFTs
    ('nft_collection_sales_volume', 'Tracks the sales volume of NFT collections on Hedera within a specific period.', 'Aggregates the value of NFT sales transactions for each collection during the specified period.'),
    ('nft_collection_sales_volume_total', 'Shows the cumulative sales volume of NFT collections on Hedera since inception.', 'Sums all NFT sales transaction values for each collection from genesis up to the specified time.'),
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
