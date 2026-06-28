-- =====================================================================
-- ecosystem.top_non_fungible_tokens_erc  (Non-Fungible Tokens)
--
-- Ranks ERC-721 NFT smart-contract collections by a weighted composite:
--   - 60% sales volume   (HBAR paid, on-chain, over a rolling window)
--   - 40% transactions   (distinct transactions touching the collection)
-- Each component is min-max scaled to [0,1]; composite = 0.6*vol + 0.4*tx.
-- Optional top-5 concentration filter (disabled by default) drops
-- collections where the top 5 payers drive > threshold of transactions.
--
-- Data source: erc.token (ERC_721), erc.nft_transfer (Transfer events),
-- public.crypto_transfer (HBAR legs). No external price source needed -
-- ERC-721 sales settle in HBAR on-chain.
--
-- On-demand ranking (rolling window relative to now); mirrors the
-- top_fungible_tokens_hts pattern. Returns SETOF a real (never-populated)
-- table so Hasura can track the function for GraphQL exposure.
--
-- Methodology: https://docs.hgraph.com/hedera-stats-wip/top-50-non-fungible-tokens
-- =====================================================================

DROP FUNCTION IF EXISTS ecosystem.top_non_fungible_tokens_erc(integer, integer, numeric) CASCADE;
DROP FUNCTION IF EXISTS ecosystem.top_non_fungible_tokens_erc(integer, integer) CASCADE;
DROP TYPE     IF EXISTS ecosystem._top_non_fungible_tokens_erc CASCADE;
DROP TABLE    IF EXISTS ecosystem._top_non_fungible_tokens_erc;

-- Empty return-shape table (never populated): a real table so Hasura can track
-- the function; column order/types must match the final SELECT (SETOF binds by position).
CREATE TABLE ecosystem._top_non_fungible_tokens_erc (
    rank                     integer,   -- Position in ranking (1 = highest score)
    token_id                 bigint,    -- ERC-721 contract token_id
    token_evm_address        text,      -- EVM address of the contract (0x...)
    collection_name          text,      -- Name of the NFT collection
    sales_volume_hbar        numeric,   -- Total HBAR sales value in window
    transaction_count        bigint,    -- Distinct transactions in window
    unique_accounts          bigint,    -- Distinct paying accounts in window
    normalized_volume        numeric,   -- Sales volume scaled to [0,1]
    normalized_transactions  numeric,   -- Transaction count scaled to [0,1]
    composite_score          numeric,   -- 0.6*norm_vol + 0.4*norm_tx
    volume_contribution      numeric,   -- norm_vol * 0.6
    tx_contribution          numeric,   -- norm_tx * 0.4
    concentration_ratio      numeric    -- share of txns from top 5 payers
);

CREATE OR REPLACE FUNCTION ecosystem.top_non_fungible_tokens_erc(
    window_hours        integer DEFAULT 720,  -- 30 days: ERC-721 sales are sparse, a short window is mostly empty
    result_limit        integer DEFAULT 50,
    exclusion_threshold numeric DEFAULT 1.0    -- concentration filter disabled by default (1.0 = no filtering)
)
RETURNS SETOF ecosystem._top_non_fungible_tokens_erc
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH params AS (
        SELECT
            GREATEST(window_hours, 1) AS win_hours,
            result_limit              AS res_limit,
            exclusion_threshold       AS excl_threshold
    ),

    time_window AS (
        SELECT
            (EXTRACT(EPOCH FROM NOW() - (p.win_hours || ' hours')::interval) * 1000000000)::bigint AS start_ts,
            (EXTRACT(EPOCH FROM NOW()) * 1000000000)::bigint AS end_ts
        FROM params p
    ),

    -- ERC-721 events in the window. Mints/transfers/burns all count as activity;
    -- HBAR value is attributed per transaction below (free mints / burns -> 0).
    erc721_events AS (
        SELECT
            nft.token_id,
            nft.consensus_timestamp,
            nft.payer_account_id
        FROM erc.nft_transfer nft
        JOIN erc.token t
          ON t.token_id = nft.token_id
         AND t.contract_type = 'ERC_721'
        WHERE nft.consensus_timestamp >= (SELECT start_ts FROM time_window)
          AND nft.consensus_timestamp <= (SELECT end_ts   FROM time_window)
          AND nft.transfer_type IN ('transfer', 'mint', 'burn')
    ),

    -- Distinct transactions per collection (one consensus_timestamp == one transaction).
    -- Note: sender/receiver_account_id are frequently NULL for pure-EVM transfers, so
    -- attribution must NOT depend on them (the prior version's filter silently zeroed all
    -- volume because `entity_id != NULL` is never true).
    collection_txns AS (
        SELECT DISTINCT token_id, consensus_timestamp, payer_account_id
        FROM erc721_events
    ),

    relevant_ts AS (
        SELECT DISTINCT consensus_timestamp FROM erc721_events
    ),

    -- Gross HBAR value per transaction, computed ONCE from crypto_transfer to avoid the
    -- nft_transfer x crypto_transfer fan-out. Sum positive legs credited to non-system
    -- accounts (entity_id > 1000 excludes nodes, 0.0.98, 0.0.800-802, treasury): this is
    -- seller proceeds + royalties = the economic sale value, net of network fees.
    tx_value AS (
        SELECT
            ct.consensus_timestamp,
            COALESCE(SUM(ct.amount) FILTER (WHERE ct.amount > 0 AND ct.entity_id > 1000), 0) AS gross_tinybar
        FROM public.crypto_transfer ct
        JOIN relevant_ts rt ON rt.consensus_timestamp = ct.consensus_timestamp
        GROUP BY ct.consensus_timestamp
    ),

    combined_metrics AS (
        SELECT
            ct.token_id,
            t.token_evm_address,
            t.name::text AS collection_name,
            COALESCE(SUM(tv.gross_tinybar), 0) / 100000000.0 AS sales_volume_hbar,
            COUNT(DISTINCT ct.consensus_timestamp)           AS transaction_count,
            COUNT(DISTINCT ct.payer_account_id)              AS unique_accounts
        FROM collection_txns ct
        LEFT JOIN tx_value tv ON tv.consensus_timestamp = ct.consensus_timestamp
        JOIN erc.token t ON t.token_id = ct.token_id AND t.contract_type = 'ERC_721'
        GROUP BY ct.token_id, t.token_evm_address, t.name
    ),

    -- Concentration: share of a collection's transactions driven by its top 5 payers.
    account_activity AS (
        SELECT token_id, payer_account_id, COUNT(DISTINCT consensus_timestamp) AS account_tx_count
        FROM erc721_events
        GROUP BY token_id, payer_account_id
    ),
    ranked_accounts AS (
        SELECT token_id, payer_account_id,
               ROW_NUMBER() OVER (PARTITION BY token_id ORDER BY account_tx_count DESC) AS account_rank
        FROM account_activity
    ),
    top5_accounts AS (
        SELECT token_id, payer_account_id FROM ranked_accounts WHERE account_rank <= 5
    ),
    concentration_stats AS (
        SELECT
            e.token_id,
            COUNT(DISTINCT e.consensus_timestamp) AS total_tx,
            COUNT(DISTINCT e.consensus_timestamp) FILTER (
                WHERE EXISTS (
                    SELECT 1 FROM top5_accounts t5
                    WHERE t5.token_id = e.token_id
                      AND t5.payer_account_id = e.payer_account_id
                )
            ) AS top5_tx
        FROM erc721_events e
        GROUP BY e.token_id
    ),

    combined_with_filter AS (
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
        SELECT
            MIN(sales_volume_hbar) AS min_volume, MAX(sales_volume_hbar) AS max_volume,
            MIN(transaction_count) AS min_tx,     MAX(transaction_count) AS max_tx
        FROM combined_with_filter
    ),

    normalized_metrics AS (
        SELECT
            cm.*,
            CASE WHEN (mmv.max_volume - mmv.min_volume) = 0 THEN 0
                 ELSE (cm.sales_volume_hbar - mmv.min_volume) / (mmv.max_volume - mmv.min_volume)
            END AS normalized_volume,
            CASE WHEN (mmv.max_tx - mmv.min_tx) = 0 THEN 0
                 ELSE (cm.transaction_count - mmv.min_tx)::numeric / (mmv.max_tx - mmv.min_tx)
            END AS normalized_transactions
        FROM combined_with_filter cm
        CROSS JOIN min_max_values mmv
    ),

    composite_scores AS (
        SELECT
            nm.*,
            (COALESCE(nm.normalized_volume, 0) * 0.6) + (nm.normalized_transactions * 0.4) AS composite_score
        FROM normalized_metrics nm
    )

    SELECT
        ROW_NUMBER() OVER (
            ORDER BY composite_score DESC, transaction_count DESC, sales_volume_hbar DESC
        )::integer AS rank,
        token_id,
        token_evm_address,
        collection_name,
        ROUND(sales_volume_hbar, 2)                            AS sales_volume_hbar,
        transaction_count,
        unique_accounts,
        ROUND(normalized_volume::numeric, 4)                   AS normalized_volume,
        ROUND(normalized_transactions::numeric, 4)             AS normalized_transactions,
        ROUND(composite_score::numeric, 4)                     AS composite_score,
        ROUND((COALESCE(normalized_volume, 0) * 0.6)::numeric, 4) AS volume_contribution,
        ROUND((normalized_transactions * 0.4)::numeric, 4)        AS tx_contribution,
        ROUND(concentration_ratio::numeric, 4)                 AS concentration_ratio
    FROM composite_scores
    ORDER BY composite_score DESC, transaction_count DESC, sales_volume_hbar DESC
    LIMIT (SELECT res_limit FROM params);
END;
$$;

COMMENT ON FUNCTION ecosystem.top_non_fungible_tokens_erc(integer, integer, numeric) IS
'Ranks top ERC-721 NFT collections by composite score (60% HBAR sales volume + 40% transactions), each min-max scaled, over a rolling window (default 720h / 30d). Sales volume = positive HBAR legs to non-system accounts (entity_id > 1000) per transaction, net of network fees. Optional top-5 payer concentration filter (default disabled, exclusion_threshold=1.0). Signature: top_non_fungible_tokens_erc(window_hours INT DEFAULT 720, result_limit INT DEFAULT 50, exclusion_threshold NUMERIC DEFAULT 1.0). Methodology: https://docs.hgraph.com/hedera-stats-wip/top-50-non-fungible-tokens';
