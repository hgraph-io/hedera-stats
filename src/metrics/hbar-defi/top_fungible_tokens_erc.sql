-- =====================================================================
-- ecosystem.top_fungible_tokens_erc  (HBAR & DeFi)
--
-- Ranks ERC-20 fungible tokens by a weighted composite of on-chain activity:
--   - 60% transactions   (distinct transactions touching the token)
--   - 40% unique holders  (distinct receiving addresses)
-- Each component is min-max scaled to [0,1]; composite = 0.6*tx + 0.4*holders.
--
-- No market-cap or volume axis (unlike the HTS sibling): ERC-20 tokens on
-- Hedera have no USD price source (0/1,886 trade on an indexable DEX, per
-- HG-2955) and ERC-20 transfers do not settle in HBAR, so neither USD value
-- nor HBAR volume is available. Ranking is therefore activity-based, mirroring
-- the top_non_fungible_tokens_erc precedent.
--
-- Data source: erc.token (ERC_20), erc.token_transfer (Transfer events).
--
-- On-demand ranking (rolling window relative to now); mirrors the
-- top_non_fungible_tokens_erc pattern. Returns SETOF a real (never-populated)
-- table so Hasura can track the function for GraphQL exposure.
--
-- Methodology: https://docs.hgraph.com/hedera-stats-wip/top-50-fungible-tokens
-- =====================================================================

DROP FUNCTION IF EXISTS ecosystem.top_fungible_tokens_erc(integer, integer) CASCADE;
DROP TABLE    IF EXISTS ecosystem._top_fungible_tokens_erc;

-- Empty return-shape table (never populated): a real table so Hasura can track
-- the function; column order/types must match the final SELECT (SETOF binds by position).
CREATE TABLE ecosystem._top_fungible_tokens_erc (
    rank                     integer,   -- Position in ranking (1 = highest score)
    token_id                 bigint,    -- ERC-20 contract token_id
    token_evm_address        text,      -- EVM address of the contract (0x...)
    token_symbol             text,      -- Token symbol
    token_name               text,      -- Token name
    transaction_count        bigint,    -- Distinct transactions in window
    unique_holders           bigint,    -- Distinct receiving addresses in window
    normalized_transactions  numeric,   -- Transaction count scaled to [0,1]
    normalized_holders       numeric,   -- Unique holders scaled to [0,1]
    composite_score          numeric,   -- 0.6*norm_tx + 0.4*norm_holders
    tx_contribution          numeric,   -- norm_tx * 0.6
    holders_contribution     numeric    -- norm_holders * 0.4
);

CREATE OR REPLACE FUNCTION ecosystem.top_fungible_tokens_erc(
    window_hours integer DEFAULT 720,  -- 30 days: ERC-20 activity is thin, a short window is mostly empty
    result_limit integer DEFAULT 50
)
RETURNS SETOF ecosystem._top_fungible_tokens_erc
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH params AS (
        SELECT
            GREATEST(window_hours, 1) AS win_hours,
            result_limit              AS res_limit
    ),

    time_window AS (
        SELECT
            (EXTRACT(EPOCH FROM NOW() - (p.win_hours || ' hours')::interval) * 1000000000)::bigint AS start_ts,
            (EXTRACT(EPOCH FROM NOW()) * 1000000000)::bigint AS end_ts
        FROM params p
    ),

    -- ERC-20 events in the window. Mints/transfers/burns all count as activity.
    erc20_events AS (
        SELECT
            tt.token_id,
            t.token_evm_address,
            t.symbol::text AS token_symbol,
            t.name::text   AS token_name,
            tt.consensus_timestamp,
            tt.receiver_evm_address
        FROM erc.token_transfer tt
        JOIN erc.token t
          ON t.token_id = tt.token_id
         AND t.contract_type = 'ERC_20'
        WHERE tt.consensus_timestamp >= (SELECT start_ts FROM time_window)
          AND tt.consensus_timestamp <= (SELECT end_ts   FROM time_window)
          AND tt.transfer_type IN ('transfer', 'mint', 'burn')
    ),

    -- One consensus_timestamp == one transaction. Holder reach counts distinct
    -- receivers, excluding the zero address (burns) which is not a real holder.
    combined_metrics AS (
        SELECT
            token_id,
            token_evm_address,
            token_symbol,
            token_name,
            COUNT(DISTINCT consensus_timestamp) AS transaction_count,
            COUNT(DISTINCT receiver_evm_address) FILTER (
                WHERE receiver_evm_address IS NOT NULL
                  AND receiver_evm_address != '0x0000000000000000000000000000000000000000'
            ) AS unique_holders
        FROM erc20_events
        GROUP BY token_id, token_evm_address, token_symbol, token_name
    ),

    min_max_values AS (
        SELECT
            MIN(transaction_count) AS min_tx,      MAX(transaction_count) AS max_tx,
            MIN(unique_holders)    AS min_holders, MAX(unique_holders)    AS max_holders
        FROM combined_metrics
    ),

    normalized_metrics AS (
        SELECT
            cm.*,
            CASE WHEN (mmv.max_tx - mmv.min_tx) = 0 THEN 0
                 ELSE (cm.transaction_count - mmv.min_tx)::numeric / (mmv.max_tx - mmv.min_tx)
            END AS normalized_transactions,
            CASE WHEN (mmv.max_holders - mmv.min_holders) = 0 THEN 0
                 ELSE (cm.unique_holders - mmv.min_holders)::numeric / (mmv.max_holders - mmv.min_holders)
            END AS normalized_holders
        FROM combined_metrics cm
        CROSS JOIN min_max_values mmv
    ),

    composite_scores AS (
        SELECT
            nm.*,
            (nm.normalized_transactions * 0.6) + (nm.normalized_holders * 0.4) AS composite_score
        FROM normalized_metrics nm
    )

    SELECT
        ROW_NUMBER() OVER (
            ORDER BY composite_score DESC, transaction_count DESC, token_id ASC
        )::integer AS rank,
        token_id,
        token_evm_address,
        token_symbol,
        token_name,
        transaction_count,
        unique_holders,
        ROUND(normalized_transactions::numeric, 4)         AS normalized_transactions,
        ROUND(normalized_holders::numeric, 4)              AS normalized_holders,
        ROUND(composite_score::numeric, 4)                 AS composite_score,
        ROUND((normalized_transactions * 0.6)::numeric, 4) AS tx_contribution,
        ROUND((normalized_holders * 0.4)::numeric, 4)      AS holders_contribution
    FROM composite_scores
    ORDER BY composite_score DESC, transaction_count DESC, token_id ASC
    LIMIT (SELECT res_limit FROM params);
END;
$$;

COMMENT ON FUNCTION ecosystem.top_fungible_tokens_erc(integer, integer) IS
'Ranks top ERC-20 fungible tokens by composite score (60% transactions + 40% unique holders), each min-max scaled, over a rolling window (default 720h / 30d). Activity-based: ERC-20 tokens on Hedera have no USD price source (per HG-2955) and ERC-20 transfers do not settle in HBAR, so no market-cap or volume axis is possible. Transactions counted are mint, transfer, and burn events from erc.token_transfer (contract_type = ERC_20), one per distinct consensus_timestamp. Unique holders counts distinct receiver EVM addresses, excluding the zero address (burns). Returns rank, token_id, token_evm_address (0x format), token_symbol, token_name, transaction_count, unique_holders, normalized metrics, composite_score, and contribution breakdown. Signature: top_fungible_tokens_erc(window_hours INT DEFAULT 720, result_limit INT DEFAULT 50). Methodology: https://docs.hgraph.com/hedera-stats-wip/top-50-fungible-tokens';
