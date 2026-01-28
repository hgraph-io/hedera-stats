-- Top 50 ERC-721 Smart Contract Collections by Composite Score with Concentration Filter
-- 
-- This function ranks ERC-721 NFT smart contracts based on a weighted composite score:
--   - 60% weight: Normalized sales volume (HBAR)
--   - 40% weight: Normalized transaction count
--
-- Data Source: erc.token (ERC-721 contracts), erc.nft_transfer (Transfer events)
-- Key Difference from HTS: Queries erc schema instead of public.token
--
-- Concentration Filter: Available but DISABLED by default (threshold=1.0)
--   - Set exclusion_threshold < 1.0 to enable filtering
--   - Excludes collections where top 5 accounts contribute >threshold of transactions
-- Methodology: https://docs.hgraph.com/hedera-stats-wip/top-50-non-fungible-tokens

-- Drop existing type and function if they exist
DROP TYPE IF EXISTS ecosystem._top_non_fungible_tokens_erc CASCADE;
DROP FUNCTION IF EXISTS ecosystem.top_non_fungible_tokens_erc(integer, integer, numeric) CASCADE;
DROP FUNCTION IF EXISTS ecosystem.top_non_fungible_tokens_erc(integer, integer) CASCADE;

-- Create custom return type
CREATE TYPE ecosystem._top_non_fungible_tokens_erc AS (
    rank integer,                      -- Position in ranking (1 = highest score)
    token_id bigint,                   -- ERC-721 contract token_id
    token_evm_address text,            -- EVM address of the contract (0x...)
    collection_name text,              -- Name of the NFT collection
    sales_volume_hbar numeric,         -- Total HBAR sales in time window
    transaction_count bigint,          -- Number of unique transactions
    unique_accounts bigint,            -- Number of unique accounts trading
    normalized_volume numeric,         -- Sales volume normalized to [0,1]
    normalized_transactions numeric,   -- Transaction count normalized to [0,1]
    composite_score numeric,           -- Final score: (vol×0.6) + (tx×0.4)
    volume_contribution numeric,       -- Volume component (normalized_volume × 0.6)
    tx_contribution numeric,           -- Transaction component (normalized_tx × 0.4)
    concentration_ratio numeric        -- % of transactions from top 5 accounts
);

-- Create the ranking function with concentration filter
CREATE OR REPLACE FUNCTION ecosystem.top_non_fungible_tokens_erc(
    window_hours integer DEFAULT 72,
    result_limit integer DEFAULT 50,
    exclusion_threshold numeric DEFAULT 1.0  -- Default: disabled (1.0 = 100%, no filtering)
)
RETURNS SETOF ecosystem._top_non_fungible_tokens_erc
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH params AS (
        SELECT 
            window_hours AS win_hours,
            result_limit AS res_limit,
            exclusion_threshold AS excl_threshold
    ),
    
    time_window AS (
        -- Define the time range for analysis (default: last 72 hours)
        SELECT 
            (EXTRACT(EPOCH FROM NOW() - (p.win_hours || ' hours')::interval) * 1000000000)::bigint AS start_ts,
            (EXTRACT(EPOCH FROM NOW()) * 1000000000)::bigint AS end_ts
        FROM params p
    ),
    
    erc721_transfers AS (
        -- Extract all ERC-721 NFT transfers in time window from erc schema
        SELECT 
            nft.token_id,
            nft.consensus_timestamp,
            nft.payer_account_id,
            nft.sender_account_id,
            nft.receiver_account_id,
            nft.transfer_type,
            t.name::text AS collection_name,
            t.token_evm_address
        FROM erc.nft_transfer nft
        JOIN erc.token t ON t.token_id = nft.token_id
            AND t.contract_type = 'ERC_721'
        WHERE nft.consensus_timestamp >= (SELECT start_ts FROM time_window)
          AND nft.consensus_timestamp <= (SELECT end_ts FROM time_window)
          AND nft.transfer_type IN ('transfer', 'mint', 'burn')  -- All transfer types
    ),
    
    transfers_with_hbar AS (
        -- Link ERC-721 transfers to HBAR payments via crypto_transfer
        SELECT 
            et.token_id,
            et.token_evm_address,
            et.collection_name,
            et.consensus_timestamp,
            et.payer_account_id,
            et.sender_account_id,
            et.receiver_account_id,
            et.transfer_type,
            ct.amount,
            ct.entity_id
        FROM erc721_transfers et
        LEFT JOIN crypto_transfer ct ON ct.consensus_timestamp = et.consensus_timestamp
    ),
    
    transaction_hbar AS (
        -- Calculate HBAR amount per transaction
        -- Exclude sender from sales volume (sender pays receiver)
        SELECT 
            token_id,
            token_evm_address,
            collection_name,
            consensus_timestamp,
            payer_account_id,
            COALESCE(
                SUM(amount) FILTER (
                    WHERE amount > 0 
                    AND entity_id != sender_account_id
                ), 
                0
            ) as hbar_tinybar
        FROM transfers_with_hbar
        GROUP BY token_id, token_evm_address, collection_name, consensus_timestamp, payer_account_id, sender_account_id
    ),
    
    combined_metrics AS (
        -- Aggregate metrics per ERC-721 collection (before concentration filter)
        SELECT 
            token_id,
            MAX(token_evm_address) AS token_evm_address,
            MAX(collection_name) AS collection_name,
            SUM(hbar_tinybar) / 100000000.0 AS sales_volume_hbar,
            COUNT(DISTINCT consensus_timestamp) AS transaction_count,
            COUNT(DISTINCT payer_account_id) AS unique_accounts
        FROM transaction_hbar
        GROUP BY token_id
    ),
    
    account_activity AS (
        -- Count transactions per account per collection
        SELECT 
            token_id,
            payer_account_id,
            COUNT(DISTINCT consensus_timestamp) AS account_tx_count
        FROM erc721_transfers
        GROUP BY token_id, payer_account_id
    ),
    
    ranked_accounts AS (
        -- Rank accounts within each collection by transaction count
        SELECT 
            token_id,
            payer_account_id,
            ROW_NUMBER() OVER (PARTITION BY token_id ORDER BY account_tx_count DESC) AS account_rank
        FROM account_activity
    ),
    
    top5_accounts AS (
        -- Identify top 5 accounts per collection
        SELECT token_id, payer_account_id
        FROM ranked_accounts
        WHERE account_rank <= 5
    ),
    
    concentration_stats AS (
        -- Calculate concentration: % of transactions from top 5 accounts
        SELECT 
            et.token_id,
            COUNT(DISTINCT et.consensus_timestamp) AS total_tx,
            COUNT(DISTINCT et.consensus_timestamp) FILTER (
                WHERE EXISTS (
                    SELECT 1 FROM top5_accounts t5 
                    WHERE t5.token_id = et.token_id 
                    AND t5.payer_account_id = et.payer_account_id
                )
            ) AS top5_tx
        FROM erc721_transfers et
        GROUP BY et.token_id
    ),
    
    combined_with_filter AS (
        -- Join metrics with concentration stats and apply filter
        SELECT 
            cm.token_id,
            cm.token_evm_address,
            cm.collection_name,
            cm.sales_volume_hbar,
            cm.transaction_count,
            cm.unique_accounts,
            COALESCE((cs.top5_tx::numeric / NULLIF(cs.total_tx, 0)), 0) AS concentration_ratio
        FROM combined_metrics cm
        LEFT JOIN concentration_stats cs ON cs.token_id = cm.token_id
        CROSS JOIN params p
        WHERE COALESCE((cs.top5_tx::numeric / NULLIF(cs.total_tx, 0)), 0) <= p.excl_threshold
    ),
    
    min_max_values AS (
        -- Calculate min/max for normalization (after concentration filter)
        SELECT 
            MIN(sales_volume_hbar) AS min_volume,
            MAX(sales_volume_hbar) AS max_volume,
            MIN(transaction_count) AS min_tx,
            MAX(transaction_count) AS max_tx
        FROM combined_with_filter
    ),
    
    normalized_metrics AS (
        -- Apply min-max normalization to scale values to [0, 1]
        SELECT 
            cm.token_id,
            cm.token_evm_address,
            cm.collection_name,
            cm.sales_volume_hbar,
            cm.transaction_count,
            cm.unique_accounts,
            cm.concentration_ratio,
            -- Normalize volume
            CASE 
                WHEN (mmv.max_volume - mmv.min_volume) = 0 THEN 0
                ELSE (cm.sales_volume_hbar - mmv.min_volume) / (mmv.max_volume - mmv.min_volume)
            END AS normalized_volume,
            -- Normalize transactions (MUST cast to numeric to avoid integer division!)
            CASE 
                WHEN (mmv.max_tx - mmv.min_tx) = 0 THEN 0
                ELSE (cm.transaction_count - mmv.min_tx)::numeric / (mmv.max_tx - mmv.min_tx)
            END AS normalized_transactions
        FROM combined_with_filter cm
        CROSS JOIN min_max_values mmv
    ),
    
    composite_scores AS (
        -- Calculate composite score: 60% volume + 40% transactions
        -- Use COALESCE to treat NULL volume as 0 (collections with no sales)
        SELECT 
            token_id,
            token_evm_address,
            collection_name,
            sales_volume_hbar,
            transaction_count,
            unique_accounts,
            concentration_ratio,
            normalized_volume,
            normalized_transactions,
            (COALESCE(normalized_volume, 0) * 0.6) + (normalized_transactions * 0.4) AS composite_score
        FROM normalized_metrics
    )
    
    -- Final ranking
    SELECT 
        ROW_NUMBER() OVER (
            ORDER BY 
                composite_score DESC, 
                transaction_count DESC,
                sales_volume_hbar DESC
        )::integer AS rank,
        token_id,
        token_evm_address,
        collection_name,
        ROUND(sales_volume_hbar, 2) AS sales_volume_hbar,
        transaction_count,
        unique_accounts,
        ROUND(normalized_volume::numeric, 4) AS normalized_volume,
        ROUND(normalized_transactions::numeric, 4) AS normalized_transactions,
        ROUND(composite_score::numeric, 4) AS composite_score,
        ROUND((COALESCE(normalized_volume, 0) * 0.6)::numeric, 4) AS volume_contribution,
        ROUND((normalized_transactions * 0.4)::numeric, 4) AS tx_contribution,
        ROUND(concentration_ratio::numeric, 4) AS concentration_ratio
    FROM composite_scores
    CROSS JOIN params p
    ORDER BY 
        composite_score DESC, 
        transaction_count DESC,
        sales_volume_hbar DESC
    LIMIT (SELECT res_limit FROM params);
END;
$$;

-- Add function comment
COMMENT ON FUNCTION ecosystem.top_non_fungible_tokens_erc IS 
'Ranks top ERC-721 smart contract NFT collections using composite score (60% volume + 40% transactions). Queries erc.token and erc.nft_transfer tables. Concentration filter available (default: disabled with threshold=1.0). Set exclusion_threshold < 1.0 to filter collections where top 5 accounts contribute >threshold of transactions.';
