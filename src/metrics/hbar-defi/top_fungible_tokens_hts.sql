-- =====================================================================
-- ecosystem.top_fungible_tokens_hts  (HBAR & DeFi)
--
-- Ranks HTS fungible tokens by a weighted composite score:
--   - 40% market cap   (DEX price x circulating supply)
--   - 40% volume       (trailing 24h DEX volume, hour candles)
--   - 20% transactions (distinct token_transfer count, mirror node)
-- Each component is log-normalized (ln(1+x)) then min-max scaled to [0,1].
-- Eligibility: a min_liquidity_hbar price-trust floor, then volume >= $100
-- or a market-cap / volume ratio under 50,000; zero-volume tokens excluded.
-- Tie-break is deterministic (composite, then volume, then token_id).
--
-- Reads dex.latest for live prices. SWITCH POINT: when the dex.latest ->
-- dex.spot_price rename lands (hg-core #1201), change the single FROM in
-- the spot_price CTE and add spot_price to the dex FDW import; nothing else.
--
-- Methodology: https://docs.hgraph.com/hedera-stats-wip/top-50-fungible-tokens
-- =====================================================================

-- Re-runnable sequence: drop the function before the table (the function
-- depends on the table type), then recreate both. No CASCADE (it would
-- desync Hasura metadata).
DROP FUNCTION IF EXISTS ecosystem.top_fungible_tokens_hts(integer, integer, numeric);
DROP TABLE IF EXISTS ecosystem._top_fungible_tokens_hts;

-- Return table: a real TABLE (relkind r) so Hasura can track the function.
-- Column order and types match the function's final SELECT exactly (SETOF
-- binds by position). token_id is declared bigint; the body casts the
-- entity_id-domain column with an explicit ::BIGINT (binary-coercible).
CREATE TABLE ecosystem._top_fungible_tokens_hts (
    rank                     integer,
    market_cap_rank          integer,
    volume_rank              integer,
    token_symbol             text,
    token_name               text,
    token_id                 bigint,
    composite_score          numeric,
    market_cap_contribution  numeric,
    volume_contribution      numeric,
    tx_contribution          numeric,
    price_usd                numeric,
    pct_change_24h           numeric,
    market_cap_usd           numeric,
    volume_usd               numeric,
    transaction_count        bigint,
    unique_accounts          bigint,
    liquidity_usd            numeric,
    normalized_market_cap    numeric,
    normalized_volume        numeric,
    normalized_transactions  numeric,
    price_as_of              timestamptz,
    bound_min_ln_mcap        numeric,
    bound_max_ln_mcap        numeric,
    bound_min_ln_vol         numeric,
    bound_max_ln_vol         numeric,
    bound_min_ln_tx          numeric,
    bound_max_ln_tx          numeric
);

-- Signature is locked to three arguments. The remaining knobs
-- (min_volume_usd, max_mcap_volume_ratio, the three weights) stay as
-- literals in the params CTE. window_hours and min_liquidity_hbar are
-- clamped (a public Hasura function must not silently invert the window or
-- disable the liquidity floor). No STRICT (it blocks inlining and adds
-- nothing with DEFAULTs); no SET search_path (it blocks inlining).
CREATE OR REPLACE FUNCTION ecosystem.top_fungible_tokens_hts(
    window_hours        integer DEFAULT 24,
    result_limit        integer DEFAULT 50,
    min_liquidity_hbar  numeric DEFAULT 1000
)
RETURNS SETOF ecosystem._top_fungible_tokens_hts
LANGUAGE sql
STABLE
PARALLEL SAFE
BEGIN ATOMIC
    WITH params AS (
        SELECT
            GREATEST(window_hours, 1)        AS window_hours,
            result_limit                     AS result_limit,
            GREATEST(min_liquidity_hbar, 0)  AS min_liquidity_hbar,
            100                              AS min_volume_usd,
            50000                            AS max_mcap_volume_ratio,
            0.4                              AS weight_market_cap,
            0.4                              AS weight_volume,
            0.2                              AS weight_transactions
    ),
    weights AS (
        SELECT
            weight_market_cap   / (weight_market_cap + weight_volume + weight_transactions) AS w_mcap,
            weight_volume       / (weight_market_cap + weight_volume + weight_transactions) AS w_vol,
            weight_transactions / (weight_market_cap + weight_volume + weight_transactions) AS w_tx
        FROM params
    ),
    bounds AS (
        SELECT
            FLOOR(EXTRACT(EPOCH FROM now()) / 3600)::bigint * 3600 * 1000000000 AS end_ns,
            (FLOOR(EXTRACT(EPOCH FROM now()) / 3600)::bigint - p.window_hours)
                * 3600 * 1000000000 AS start_ns
        FROM params p
    ),
    spot_price AS (
        -- Live board. Switch the FROM to dex.spot_price once the rename
        -- lands (hg-core #1201); column parity assumed, assert post-rename.
        SELECT token_id, source, price_usd, price_hbar, liquidity_hbar, consensus_timestamp
        FROM dex.latest
    ),
    selected_price AS (
        SELECT DISTINCT ON (token_id)
            token_id, source, price_usd, price_hbar, liquidity_hbar, consensus_timestamp
        FROM spot_price
        ORDER BY token_id, liquidity_hbar DESC NULLS LAST, consensus_timestamp DESC, source
    ),
    candidates AS (
        SELECT
            t.token_id,
            t.name::text   AS token_name,
            t.symbol::text AS token_symbol,
            sp.source      AS price_source,
            sp.price_usd,
            sp.liquidity_hbar,
            sp.consensus_timestamp AS price_consensus_timestamp,
            sp.liquidity_hbar * sp.price_usd / NULLIF(sp.price_hbar, 0) AS liquidity_usd,
            (t.total_supply / POWER(10, COALESCE(t.decimals, 0))) * sp.price_usd AS market_cap_usd
        FROM selected_price sp
        JOIN public.token t ON t.token_id = sp.token_id
        WHERE t.type = 'FUNGIBLE_COMMON'   -- token_type enum; coerced from the literal
          AND sp.price_usd > 0
          AND t.total_supply > 0
    ),
    vol AS (
        SELECT c.token_id, SUM(c.volume_usd) AS volume_usd
        FROM dex.candle c
        CROSS JOIN bounds b
        WHERE c.period = 'hour'
          AND lower(c.timestamp_range) >= b.start_ns
          AND lower(c.timestamp_range) <  b.end_ns
        GROUP BY c.token_id
    ),
    px_change AS (
        SELECT
            c.token_id,
            100.0 * ((ARRAY_AGG(c.close_usd ORDER BY lower(c.timestamp_range) DESC))[1]
                   - (ARRAY_AGG(c.open_usd  ORDER BY lower(c.timestamp_range) ASC))[1])
                  / NULLIF((ARRAY_AGG(c.open_usd ORDER BY lower(c.timestamp_range) ASC))[1], 0)
                AS pct_change_24h
        FROM dex.candle c
        JOIN selected_price sp ON sp.token_id = c.token_id AND sp.source = c.source
        CROSS JOIN bounds b
        WHERE c.period = 'hour'
          AND lower(c.timestamp_range) >= b.start_ns
          AND lower(c.timestamp_range) <  b.end_ns
        GROUP BY c.token_id
    ),
    survivors AS (
        SELECT
            ca.*,
            COALESCE(v.volume_usd, 0) AS volume_usd,
            px.pct_change_24h
        FROM candidates ca
        LEFT JOIN vol v        ON v.token_id  = ca.token_id
        LEFT JOIN px_change px ON px.token_id = ca.token_id
        CROSS JOIN params p
        WHERE ca.liquidity_hbar IS NOT NULL
          AND ca.liquidity_hbar >= p.min_liquidity_hbar
          AND (
                COALESCE(v.volume_usd, 0) >= p.min_volume_usd
             OR (ca.market_cap_usd / NULLIF(COALESCE(v.volume_usd, 0), 0) < p.max_mcap_volume_ratio
                 AND COALESCE(v.volume_usd, 0) > 0)
          )
    ),
    tx AS (
        SELECT
            tt.token_id,
            COUNT(DISTINCT tt.consensus_timestamp) AS transaction_count,
            COUNT(DISTINCT tt.account_id)          AS unique_accounts
        FROM public.token_transfer tt
        CROSS JOIN bounds b
        WHERE tt.consensus_timestamp >= b.start_ns
          AND tt.consensus_timestamp <  b.end_ns
          -- BIGINT casts + the ARRAY(...) form are required for fdw pushdown
          -- (the entity_id domain; FDW-import context only, not native).
          AND tt.token_id::bigint = ANY (ARRAY(SELECT token_id::bigint FROM survivors))
        GROUP BY tt.token_id
    ),
    scored AS (
        SELECT
            s.*,
            COALESCE(t.transaction_count, 0) AS transaction_count,
            COALESCE(t.unique_accounts, 0)   AS unique_accounts,
            LN(1 + s.market_cap_usd)                 AS ln_mcap,
            LN(1 + s.volume_usd)                     AS ln_vol,
            LN(1 + COALESCE(t.transaction_count, 0)) AS ln_tx
        FROM survivors s
        LEFT JOIN tx t ON t.token_id = s.token_id
    ),
    normalized AS (
        SELECT
            sc.*,
            (sc.ln_mcap - MIN(sc.ln_mcap) OVER ())
                / NULLIF(MAX(sc.ln_mcap) OVER () - MIN(sc.ln_mcap) OVER (), 0) AS norm_mcap,
            (sc.ln_vol - MIN(sc.ln_vol) OVER ())
                / NULLIF(MAX(sc.ln_vol) OVER () - MIN(sc.ln_vol) OVER (), 0)   AS norm_vol,
            (sc.ln_tx - MIN(sc.ln_tx) OVER ())
                / NULLIF(MAX(sc.ln_tx) OVER () - MIN(sc.ln_tx) OVER (), 0)     AS norm_tx,
            MIN(sc.ln_mcap) OVER () AS bound_min_ln_mcap,
            MAX(sc.ln_mcap) OVER () AS bound_max_ln_mcap,
            MIN(sc.ln_vol)  OVER () AS bound_min_ln_vol,
            MAX(sc.ln_vol)  OVER () AS bound_max_ln_vol,
            MIN(sc.ln_tx)   OVER () AS bound_min_ln_tx,
            MAX(sc.ln_tx)   OVER () AS bound_max_ln_tx
        FROM scored sc
    ),
    composite AS (
        SELECT
            n.*,
            w.w_mcap * COALESCE(n.norm_mcap, 0) AS market_cap_contribution,
            w.w_vol  * COALESCE(n.norm_vol, 0)  AS volume_contribution,
            w.w_tx   * COALESCE(n.norm_tx, 0)   AS tx_contribution,
            w.w_mcap * COALESCE(n.norm_mcap, 0)
          + w.w_vol  * COALESCE(n.norm_vol, 0)
          + w.w_tx   * COALESCE(n.norm_tx, 0)   AS composite_score
        FROM normalized n
        CROSS JOIN weights w
    )
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY c.composite_score DESC, c.volume_usd DESC, c.token_id ASC
        )::integer                                                                  AS rank,
        ROW_NUMBER() OVER (ORDER BY c.market_cap_usd DESC, c.token_id ASC)::integer AS market_cap_rank,
        ROW_NUMBER() OVER (ORDER BY c.volume_usd DESC, c.token_id ASC)::integer     AS volume_rank,
        c.token_symbol,
        c.token_name,
        c.token_id::bigint                            AS token_id,
        ROUND(c.composite_score::numeric, 4)          AS composite_score,
        ROUND(c.market_cap_contribution::numeric, 4)  AS market_cap_contribution,
        ROUND(c.volume_contribution::numeric, 4)      AS volume_contribution,
        ROUND(c.tx_contribution::numeric, 4)          AS tx_contribution,
        ROUND(c.price_usd::numeric, 6)                AS price_usd,
        ROUND(c.pct_change_24h::numeric, 2)           AS pct_change_24h,
        ROUND(c.market_cap_usd::numeric, 2)           AS market_cap_usd,
        ROUND(c.volume_usd::numeric, 2)               AS volume_usd,
        c.transaction_count,
        c.unique_accounts,
        ROUND(c.liquidity_usd::numeric, 2)            AS liquidity_usd,
        ROUND(COALESCE(c.norm_mcap, 0)::numeric, 4)   AS normalized_market_cap,
        ROUND(COALESCE(c.norm_vol, 0)::numeric, 4)    AS normalized_volume,
        ROUND(COALESCE(c.norm_tx, 0)::numeric, 4)     AS normalized_transactions,
        -- to_timestamp yields timestamptz at UTC; do NOT wrap in AT TIME ZONE.
        to_timestamp(c.price_consensus_timestamp / 1000000000) AS price_as_of,
        ROUND(c.bound_min_ln_mcap::numeric, 6)        AS bound_min_ln_mcap,
        ROUND(c.bound_max_ln_mcap::numeric, 6)        AS bound_max_ln_mcap,
        ROUND(c.bound_min_ln_vol::numeric, 6)         AS bound_min_ln_vol,
        ROUND(c.bound_max_ln_vol::numeric, 6)         AS bound_max_ln_vol,
        ROUND(c.bound_min_ln_tx::numeric, 6)          AS bound_min_ln_tx,
        ROUND(c.bound_max_ln_tx::numeric, 6)          AS bound_max_ln_tx
    FROM composite c
    ORDER BY c.composite_score DESC, c.volume_usd DESC, c.token_id ASC
    LIMIT GREATEST(COALESCE((SELECT result_limit FROM params), 0), 0);
END;

-- Catalog summary (mirrors the metric_descriptions row).
COMMENT ON FUNCTION ecosystem.top_fungible_tokens_hts(integer, integer, numeric) IS
'Ranks top HTS fungible tokens by a composite score (40% market cap + 40% DEX volume + 20% transactions), each component log-normalized then min-max scaled, over a rolling window (default 24h). Signature: top_fungible_tokens_hts(window_hours INT DEFAULT 24, result_limit INT DEFAULT 50, min_liquidity_hbar NUMERIC DEFAULT 1000). Methodology: https://docs.hgraph.com/hedera-stats-wip/top-50-fungible-tokens';
