-- =====================================================================
-- PoC: top_fungible_tokens_hts (HG-2956, phase 1) - v6, 2026-06-07
-- The workbench. Output = the future function's output at default knobs
--   (anchor 0, live board), plus a marked DEBUG block. anchor_hours_ago
--   reconstructs the board as of any past hour from candles.
-- v6 adds parity columns: price_as_of (price staleness, honest live board)
--   and the 6 normalization bounds (Phase-2 feed); display norms COALESCE
--   to 0 so a degenerate component never renders NULL beside a 0 contribution.
-- Manual: tuning-guide.md | Methodology: ../2026-06-03-top-fungible-tokens-hts-phase-1.md
-- Conversion checklist: README.md | Run evidence: validation-results.md
-- Comments stay free of DDL/cursor keywords (run-harness constraint).
-- =====================================================================

-- 1. CONTROLS ---------------------------------------------------------
-- First three mirror the locked function signature; the rest are
-- PoC-only tuning knobs, kept as literals at conversion (README item 1).
-- Weight style: decimals summing to 1.0. The weights CTE divides by the
-- sum, so ratio inputs behave identically; all-zero weights fail loudly.
-- anchor_hours_ago: 0 = live board (spot prices; the function profile).
--   N = the board as of N complete hours ago, fully reconstructed from
--   hour candles (price, liquidity, supply all as-of that hour).

WITH params AS (
    SELECT
        24    AS window_hours,   -- presets: hour 1, day 24, week 168, month 720
        50    AS result_limit,
        1000  AS min_liquidity_hbar,
        100   AS min_volume_usd,
        50000 AS max_mcap_volume_ratio,
        0.4   AS weight_market_cap,
        0.4   AS weight_volume,
        0.2   AS weight_transactions,
        0     AS anchor_hours_ago
),

weights AS (
    SELECT
        weight_market_cap   / (weight_market_cap + weight_volume + weight_transactions) AS w_mcap,
        weight_volume       / (weight_market_cap + weight_volume + weight_transactions) AS w_vol,
        weight_transactions / (weight_market_cap + weight_volume + weight_transactions) AS w_tx
    FROM params
),

-- 2. TIME BOUNDS ------------------------------------------------------

bounds AS (
    SELECT
        (FLOOR(EXTRACT(EPOCH FROM now()) / 3600)::BIGINT - p.anchor_hours_ago)
            * 3600 * 1000000000 AS end_ns,
        (FLOOR(EXTRACT(EPOCH FROM now()) / 3600)::BIGINT - p.anchor_hours_ago - p.window_hours)
            * 3600 * 1000000000 AS start_ns
    FROM params p
),

-- 3. PRICE SELECTION --------------------------------------------------

spot_price AS (
    -- Live branch (anchor 0). Builds against dex.latest, which is live in
    -- prod now, so the query runs today. SWITCH POINT: once dex.spot_price
    -- goes live in prod (hg-core #1201), change the single FROM below to
    -- dex.spot_price; nothing else changes (column parity is assumed and
    -- must be verified once dex.spot_price is live).
    SELECT
        token_id,
        source,
        price_usd,
        price_hbar,
        liquidity_hbar,
        consensus_timestamp
    FROM dex.latest   -- switch to dex.spot_price once it goes live (hg-core #1201)
    WHERE (SELECT anchor_hours_ago FROM params) = 0
    UNION ALL
    -- Anchored branch: last hour candle per (token, source) within a
    -- 30-day lookback before the anchor (staleness policy; the 720h
    -- literal is independent of the month window preset; candle-backed
    -- sources only, derived sources have no candles).
    SELECT
        token_id,
        source,
        price_usd,
        price_hbar,
        liquidity_hbar,
        consensus_timestamp
    FROM (
        SELECT DISTINCT ON (c.token_id, c.source)
            c.token_id,
            c.source,
            c.close_usd  AS price_usd,
            c.close_hbar AS price_hbar,
            c.liquidity_hbar,
            lower(c.timestamp_range) AS consensus_timestamp
        FROM dex.candle c
        CROSS JOIN bounds b
        WHERE (SELECT anchor_hours_ago FROM params) > 0
          AND c.period = 'hour'
          AND lower(c.timestamp_range) <  b.end_ns
          AND lower(c.timestamp_range) >= b.end_ns - 720::BIGINT * 3600 * 1000000000
        ORDER BY c.token_id, c.source, lower(c.timestamp_range) DESC
    ) anchored
),

selected_price AS (
    SELECT DISTINCT ON (token_id)
        token_id,
        source,
        price_usd,
        price_hbar,
        liquidity_hbar,
        consensus_timestamp
    FROM spot_price
    ORDER BY token_id, liquidity_hbar DESC NULLS LAST, consensus_timestamp DESC, source
),

-- 4. ELIGIBILITY ------------------------------------------------------

candidates AS (
    SELECT
        t.token_id,
        t.name::TEXT   AS token_name,
        t.symbol::TEXT AS token_symbol,
        sp.source      AS price_source,
        sp.price_usd,
        sp.liquidity_hbar,
        sp.consensus_timestamp AS price_consensus_timestamp,
        sp.liquidity_hbar * sp.price_usd / NULLIF(sp.price_hbar, 0) AS liquidity_usd,
        sup.supply_asof,
        (sup.supply_asof / POWER(10, COALESCE(t.decimals, 0))) * sp.price_usd AS market_cap_usd
    FROM selected_price sp
    JOIN public.token t ON t.token_id = sp.token_id
    CROSS JOIN params p
    CROSS JOIN bounds b
    CROSS JOIN LATERAL (
        SELECT CASE WHEN p.anchor_hours_ago = 0 THEN t.total_supply::NUMERIC
                    ELSE COALESCE(
                        (SELECT tk.total_supply FROM public.token tk
                         WHERE tk.token_id = sp.token_id AND tk.timestamp_range @> b.end_ns),
                        (SELECT th.total_supply FROM public.token_history th
                         WHERE th.token_id = sp.token_id AND th.timestamp_range @> b.end_ns)
                    )::NUMERIC
               END AS supply_asof
    ) sup
    WHERE t.type = 'FUNGIBLE_COMMON'
      AND sp.price_usd > 0
),

vol AS (
    SELECT
        c.token_id,
        SUM(c.volume_usd) AS volume_usd
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
        px.pct_change_24h,
        CASE WHEN COALESCE(v.volume_usd, 0) >= p.min_volume_usd
             THEN 'volume_floor' ELSE 'ratio' END AS eligibility_clause
    FROM candidates ca
    LEFT JOIN vol v        ON v.token_id  = ca.token_id
    LEFT JOIN px_change px ON px.token_id = ca.token_id
    CROSS JOIN params p
    WHERE ca.liquidity_hbar IS NOT NULL
      AND ca.liquidity_hbar >= p.min_liquidity_hbar
      AND ca.supply_asof > 0
      AND (
            COALESCE(v.volume_usd, 0) >= p.min_volume_usd
         OR (ca.market_cap_usd / NULLIF(COALESCE(v.volume_usd, 0), 0) < p.max_mcap_volume_ratio
             AND COALESCE(v.volume_usd, 0) > 0)
      )
),

-- 5. SCORING ----------------------------------------------------------

tx AS (
    SELECT
        tt.token_id,
        COUNT(DISTINCT tt.consensus_timestamp) AS transaction_count,
        COUNT(DISTINCT tt.account_id)          AS unique_accounts
    FROM public.token_transfer tt
    CROSS JOIN bounds b
    WHERE tt.consensus_timestamp >= b.start_ns
      AND tt.consensus_timestamp <  b.end_ns
      -- The BIGINT casts and the ARRAY(...) form are required for fdw
      -- pushdown (validation-results.md, battery 4).
      AND tt.token_id::BIGINT = ANY (ARRAY(SELECT token_id::BIGINT FROM survivors))
    GROUP BY tt.token_id
),

scored AS (
    SELECT
        s.*,
        COALESCE(t.transaction_count, 0) AS transaction_count,
        COALESCE(t.unique_accounts, 0)   AS unique_accounts,
        LN(1 + s.market_cap_usd)                     AS ln_mcap,
        LN(1 + s.volume_usd)                         AS ln_vol,
        LN(1 + COALESCE(t.transaction_count, 0))     AS ln_tx
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
        -- Per-run normalization bounds, surfaced as parity columns so a
        -- Phase-2 snapshot can reproduce/audit the run without persisting
        -- the membership-dependent composite. Constant across rows within a
        -- run; the rows defining each minimum rank below the top-N, so these
        -- bounds cannot be recovered from a top-N payload otherwise.
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

-- 6. OUTPUT -----------------------------------------------------------

SELECT
    -- function-parity columns
    ROW_NUMBER() OVER (
        ORDER BY c.composite_score DESC, c.volume_usd DESC, c.token_id ASC
    )::INTEGER                                                                  AS rank,
    ROW_NUMBER() OVER (ORDER BY c.market_cap_usd DESC, c.token_id ASC)::INTEGER AS market_cap_rank,
    ROW_NUMBER() OVER (ORDER BY c.volume_usd DESC, c.token_id ASC)::INTEGER     AS volume_rank,
    c.token_symbol,
    c.token_name,
    c.token_id,
    ROUND(c.composite_score::NUMERIC, 4)          AS composite_score,
    ROUND(c.market_cap_contribution::NUMERIC, 4)  AS market_cap_contribution,
    ROUND(c.volume_contribution::NUMERIC, 4)      AS volume_contribution,
    ROUND(c.tx_contribution::NUMERIC, 4)          AS tx_contribution,
    ROUND(c.price_usd::NUMERIC, 6)                AS price_usd,
    ROUND(c.pct_change_24h::NUMERIC, 2)           AS pct_change_24h,
    ROUND(c.market_cap_usd::NUMERIC, 2)           AS market_cap_usd,
    ROUND(c.volume_usd::NUMERIC, 2)               AS volume_usd,
    c.transaction_count,
    c.unique_accounts,
    ROUND(c.liquidity_usd::NUMERIC, 2)            AS liquidity_usd,
    ROUND(COALESCE(c.norm_mcap, 0)::NUMERIC, 4)   AS normalized_market_cap,
    ROUND(COALESCE(c.norm_vol, 0)::NUMERIC, 4)    AS normalized_volume,
    ROUND(COALESCE(c.norm_tx, 0)::NUMERIC, 4)     AS normalized_transactions,
    -- price_as_of: the selected price row's consensus time, so a live-board
    -- consumer can see price staleness. to_timestamp yields timestamptz at
    -- UTC directly; do NOT wrap in AT TIME ZONE (that strips the zone and
    -- misreads the instant under a non-UTC session).
    to_timestamp(c.price_consensus_timestamp / 1000000000) AS price_as_of,
    -- normalization bounds (parity columns; Phase-2 feed)
    ROUND(c.bound_min_ln_mcap::NUMERIC, 6)        AS bound_min_ln_mcap,
    ROUND(c.bound_max_ln_mcap::NUMERIC, 6)        AS bound_max_ln_mcap,
    ROUND(c.bound_min_ln_vol::NUMERIC, 6)         AS bound_min_ln_vol,
    ROUND(c.bound_max_ln_vol::NUMERIC, 6)         AS bound_max_ln_vol,
    ROUND(c.bound_min_ln_tx::NUMERIC, 6)          AS bound_min_ln_tx,
    ROUND(c.bound_max_ln_tx::NUMERIC, 6)          AS bound_max_ln_tx,
    -- DEBUG (removed at conversion)
    (SELECT to_timestamp(end_ns / 1000000000) AT TIME ZONE 'UTC' FROM bounds) AS window_end_utc,
    c.eligibility_clause,
    c.price_source,
    ROUND(c.ln_mcap::NUMERIC, 4)                  AS ln_mcap,
    ROUND(c.ln_vol::NUMERIC, 4)                   AS ln_vol,
    ROUND(c.ln_tx::NUMERIC, 4)                    AS ln_tx
FROM composite c
ORDER BY c.composite_score DESC, c.volume_usd DESC, c.token_id ASC
LIMIT GREATEST(COALESCE((SELECT result_limit FROM params), 0), 0);
