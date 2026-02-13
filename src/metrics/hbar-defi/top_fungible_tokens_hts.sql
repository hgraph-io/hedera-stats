-- ============================================================================
-- Top Fungible Tokens (HTS) - Algorithmic Ranking Function
-- ============================================================================
-- Category: HBAR & DeFi
-- Description: Ranks HTS fungible tokens by composite score based on
--              market cap (40%), volume (40%), and transactions (20%)
-- Data Sources: Hedera Mirror Node, SaucerSwap API
-- 
-- Exclusion Criteria:
-- - Tokens with inflated market caps due to low liquidity
--   * Requires minimum $100 volume OR market cap/volume ratio < 50,000:1
--   * Excludes tokens with $0 volume AND market cap > $10,000
-- 
-- Methodology: https://docs.hgraph.com/hedera-stats-wip/top-50-fungible-tokens
-- ============================================================================

-- Drop existing type and function if they exist
DROP TYPE IF EXISTS ecosystem._top_fungible_tokens_hts CASCADE;
DROP FUNCTION IF EXISTS ecosystem.top_fungible_tokens_hts(text, bigint, text) CASCADE;
DROP FUNCTION IF EXISTS ecosystem.top_fungible_tokens_hts(integer, integer) CASCADE;

-- Create custom return type
CREATE TYPE ecosystem._top_fungible_tokens_hts AS (
    rank INTEGER,                       -- Position in ranking (1 = highest score)
    token_id entity_id,                 -- Hedera token ID 
    token_name TEXT,                    -- Name of the token
    token_symbol TEXT,                  -- Token ticker symbol
    price_usd NUMERIC,                  -- Current USD price (from SaucerSwap)
    market_cap_usd NUMERIC,             -- Total market capitalization
    volume_usd NUMERIC,                 -- Trading volume in time window
    transaction_count BIGINT,           -- Number of unique transactions
    normalized_market_cap NUMERIC,      -- Market cap normalized to [0,1]
    normalized_volume NUMERIC,          -- Volume normalized to [0,1]
    normalized_transactions NUMERIC,    -- Transaction count normalized to [0,1]
    composite_score NUMERIC,            -- Final score: (mc×0.4) + (vol×0.4) + (tx×0.2)
    market_cap_contribution NUMERIC,    -- Market cap component (normalized_market_cap × 0.4)
    volume_contribution NUMERIC,        -- Volume component (normalized_volume × 0.4)
    tx_contribution NUMERIC             -- Transaction component (normalized_transactions × 0.2)
);

-- Create the ranking function
CREATE OR REPLACE FUNCTION ecosystem.top_fungible_tokens_hts(
    window_hours INTEGER DEFAULT 24,    -- Analysis time window (default: 24 hours)
    result_limit INTEGER DEFAULT 50     -- Number of results to return (default: 50)
)
RETURNS SETOF ecosystem._top_fungible_tokens_hts
LANGUAGE plpgsql
AS $$
DECLARE
    current_db TEXT;
    api_url TEXT;
    api_key TEXT;
    start_timestamp BIGINT;
    end_timestamp BIGINT;
BEGIN
    -- Auto-detect environment from database name
    SELECT current_database() INTO current_db;
    
    -- Load API credentials from configuration table
    IF current_db LIKE '%testnet%' THEN
        SELECT ac.api_url, ac.api_key INTO api_url, api_key
        FROM ecosystem.api_config ac
        WHERE ac.service_name = 'saucerswap' AND ac.environment = 'testnet';
    ELSE
        SELECT ac.api_url, ac.api_key INTO api_url, api_key
        FROM ecosystem.api_config ac
        WHERE ac.service_name = 'saucerswap' AND ac.environment = 'mainnet';
    END IF;
    
    -- Verify credentials are configured
    IF api_url IS NULL OR api_key IS NULL THEN
        RAISE EXCEPTION 'SaucerSwap API credentials not found in ecosystem.api_config table.';
    END IF;
    
    -- Calculate time window (rolling window from NOW)
    end_timestamp := (EXTRACT(EPOCH FROM NOW()) * 1000000000)::BIGINT;
    start_timestamp := end_timestamp - (window_hours::BIGINT * 3600 * 1000000000);
    
    RETURN QUERY
    WITH 
    -- Step 1: Fetch SaucerSwap API prices (bulk)
    saucerswap_api AS (
        SELECT 
            status,
            CASE 
                WHEN status = 200 THEN content::jsonb
                ELSE NULL
            END as response_data
        FROM http((
            'GET',
            api_url,
            ARRAY[http_header('x-api-key', api_key)],
            NULL,
            NULL
        )::http_request)
    ),
    
    -- Step 2: Parse token prices from API
    saucerswap_prices AS (
        SELECT 
            CAST(SPLIT_PART(token_data->>'id', '.', 3) AS BIGINT) as token_id,
            token_data->>'symbol' as ss_symbol,
            token_data->>'name' as ss_name,
            CAST(token_data->>'priceUsd' AS NUMERIC) as price_usd,
            CAST(token_data->>'decimals' AS INTEGER) as decimals
        FROM saucerswap_api,
        LATERAL jsonb_array_elements(response_data) as token_data
        WHERE status = 200
          AND token_data->>'priceUsd' IS NOT NULL
          AND CAST(token_data->>'priceUsd' AS NUMERIC) > 0
    ),
    
    -- Step 3: Join with HTS tokens and calculate market cap
    token_market_caps AS (
        SELECT 
            t.token_id,
            t.symbol::TEXT as db_symbol,
            t.name::TEXT as db_name,
            t.type,
            s.price_usd,
            s.decimals as ss_decimals,
            t.total_supply,
            -- Market Cap = (total_supply / 10^decimals) * price_usd
            CASE 
                WHEN t.total_supply IS NOT NULL 
                 AND s.decimals IS NOT NULL 
                 AND s.price_usd IS NOT NULL
                 AND t.total_supply > 0
                THEN (t.total_supply::NUMERIC / POWER(10, s.decimals)) * s.price_usd
                ELSE 0
            END as market_cap_usd
        FROM saucerswap_prices s
        INNER JOIN public.token t ON s.token_id = t.token_id
        WHERE t.type = 'FUNGIBLE_COMMON'
          AND t.total_supply IS NOT NULL
          AND t.total_supply > 0
    ),
    
    -- Step 4: Calculate trading volume and transactions
    token_volumes AS (
        SELECT 
            tt.token_id,
            COUNT(DISTINCT tt.consensus_timestamp) as transfer_count,
            SUM(ABS(tt.amount)) as total_amount
        FROM token_transfer tt
        WHERE tt.consensus_timestamp BETWEEN start_timestamp AND end_timestamp
          AND tt.token_id IN (SELECT token_id FROM token_market_caps)
        GROUP BY tt.token_id
    ),
    
    -- Step 5: Calculate volume in USD
    token_volume_usd AS (
        SELECT 
            tmc.token_id,
            tv.transfer_count,
            tv.total_amount,
            -- Volume USD = (total_amount / 10^decimals) * price_usd
            CASE 
                WHEN tv.total_amount IS NOT NULL 
                 AND tmc.ss_decimals IS NOT NULL 
                 AND tmc.price_usd IS NOT NULL
                 AND tv.total_amount > 0
                THEN (tv.total_amount::NUMERIC / POWER(10, tmc.ss_decimals)) * tmc.price_usd
                ELSE 0
            END as volume_usd
        FROM token_market_caps tmc
        LEFT JOIN token_volumes tv ON tmc.token_id = tv.token_id
    ),
    
    -- Step 6: Combine all metrics
    combined_metrics AS (
        SELECT 
            tmc.token_id,
            tmc.db_symbol,
            tmc.db_name,
            tmc.price_usd,
            tmc.market_cap_usd,
            COALESCE(tvu.volume_usd, 0) as volume_usd_24h,
            COALESCE(tvu.transfer_count, 0) as tx_count
        FROM token_market_caps tmc
        LEFT JOIN token_volume_usd tvu ON tmc.token_id = tvu.token_id
        WHERE tmc.market_cap_usd > 0  -- Only tokens with valid market cap
          AND tmc.price_usd BETWEEN 0.000001 AND 10000000  -- Reasonable price range
          -- Exclusion: Tokens with inflated market caps due to low liquidity
          AND (
              -- Either has reasonable volume (>$100 minimum)
              COALESCE(tvu.volume_usd, 0) >= 100
              -- OR market cap to volume ratio is reasonable (<50,000:1)
              OR (
                  tmc.market_cap_usd / NULLIF(COALESCE(tvu.volume_usd, 0), 0) < 50000
                  AND COALESCE(tvu.volume_usd, 0) > 0
              )
          )
          -- Additional safety: exclude tokens with zero volume AND high market cap (>$10k)
          AND NOT (COALESCE(tvu.volume_usd, 0) = 0 AND tmc.market_cap_usd > 10000)
    ),
    
    -- Step 7: Normalize metrics (min-max normalization)
    normalized_metrics AS (
        SELECT 
            cm.*,
            -- Normalize market cap: (value - min) / (max - min)
            CASE 
                WHEN MAX(cm.market_cap_usd) OVER () = MIN(cm.market_cap_usd) OVER () 
                  OR MAX(cm.market_cap_usd) OVER () IS NULL 
                  OR MIN(cm.market_cap_usd) OVER () IS NULL 
                THEN 0
                ELSE (cm.market_cap_usd - MIN(cm.market_cap_usd) OVER ()) / 
                     (MAX(cm.market_cap_usd) OVER () - MIN(cm.market_cap_usd) OVER ())
            END AS norm_market_cap,
            -- Normalize volume: (value - min) / (max - min)
            CASE 
                WHEN MAX(cm.volume_usd_24h) OVER () = MIN(cm.volume_usd_24h) OVER () 
                  OR MAX(cm.volume_usd_24h) OVER () IS NULL 
                  OR MIN(cm.volume_usd_24h) OVER () IS NULL 
                THEN 0
                ELSE (cm.volume_usd_24h - MIN(cm.volume_usd_24h) OVER ()) / 
                     (MAX(cm.volume_usd_24h) OVER () - MIN(cm.volume_usd_24h) OVER ())
            END AS norm_volume,
            -- Normalize transaction count: (value - min) / (max - min)
            CASE 
                WHEN MAX(cm.tx_count) OVER () = MIN(cm.tx_count) OVER () 
                  OR MAX(cm.tx_count) OVER () IS NULL 
                  OR MIN(cm.tx_count) OVER () IS NULL 
                THEN 0
                ELSE (cm.tx_count::NUMERIC - MIN(cm.tx_count) OVER ()) / 
                     (MAX(cm.tx_count) OVER () - MIN(cm.tx_count) OVER ())
            END AS norm_tx
        FROM combined_metrics cm
    ),
    
    -- Step 8: Calculate composite score with contributions
    composite_scores AS (
        SELECT 
            nm.token_id,
            nm.db_symbol,
            nm.db_name,
            nm.price_usd,
            nm.market_cap_usd,
            nm.volume_usd_24h,
            nm.tx_count,
            nm.norm_market_cap,
            nm.norm_volume,
            nm.norm_tx,
            -- Calculate individual contributions
            (nm.norm_market_cap * 0.4) AS market_cap_contribution,
            (nm.norm_volume * 0.4) AS volume_contribution,
            (nm.norm_tx * 0.2) AS tx_contribution,
            -- Composite Score: 40% market cap + 40% volume + 20% transactions
            (nm.norm_market_cap * 0.4) + (nm.norm_volume * 0.4) + (nm.norm_tx * 0.2) AS composite_score
        FROM normalized_metrics nm
    )
    
    -- Step 9: Final ranking
    SELECT 
        ROW_NUMBER() OVER (
            ORDER BY 
                composite_score DESC, 
                market_cap_usd DESC,
                volume_usd_24h DESC
        )::INTEGER AS rank,
        token_id,
        db_name AS token_name,
        db_symbol AS token_symbol,
        ROUND(price_usd::NUMERIC, 6) AS price_usd,
        ROUND(market_cap_usd::NUMERIC, 2) AS market_cap_usd,
        ROUND(volume_usd_24h::NUMERIC, 2) AS volume_usd,
        tx_count AS transaction_count,
        ROUND(norm_market_cap::NUMERIC, 4) AS normalized_market_cap,
        ROUND(norm_volume::NUMERIC, 4) AS normalized_volume,
        ROUND(norm_tx::NUMERIC, 4) AS normalized_transactions,
        ROUND(composite_score::NUMERIC, 4) AS composite_score,
        ROUND(market_cap_contribution::NUMERIC, 4) AS market_cap_contribution,
        ROUND(volume_contribution::NUMERIC, 4) AS volume_contribution,
        ROUND(tx_contribution::NUMERIC, 4) AS tx_contribution
    FROM composite_scores
    WHERE composite_score > 0  
    ORDER BY 
        composite_score DESC, 
        market_cap_usd DESC,
        volume_usd_24h DESC
    LIMIT result_limit;
END;
$$;

