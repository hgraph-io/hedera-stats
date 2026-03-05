-- Total ERC-1400 (security token standard) accounts as of each period.
-- Counts unique accounts that have ever been associated with an ERC-1400 token.

CREATE OR REPLACE FUNCTION ecosystem.total_erc1400_accounts(
    period TEXT,
    start_timestamp BIGINT DEFAULT 0,
    end_timestamp BIGINT DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000000000)::BIGINT
)
RETURNS SETOF ecosystem.metric_total
LANGUAGE sql STABLE
AS $$

WITH

-- Step 1: All ERC-1400 token IDs (pre-classified by the ERC indexer).
erc1400_tokens AS (
    SELECT token_id
    FROM erc.token
    WHERE contract_type = 'ERC_1400'
),

-- Step 2: Count accounts first associated BEFORE the query window (baseline).
base_holders AS (
    SELECT COUNT(DISTINCT account_id) AS base
    FROM erc.token_account
    WHERE token_id IN (SELECT token_id FROM erc1400_tokens)
      AND created_timestamp < start_timestamp
),

-- Step 3: Per-account earliest association timestamp within the window.
-- MIN() deduplicates accounts associated with multiple ERC-1400 tokens (count each once).
window_first_hold AS (
    SELECT
        account_id,
        MIN(created_timestamp) AS first_ts
    FROM erc.token_account
    WHERE token_id IN (SELECT token_id FROM erc1400_tokens)
      AND created_timestamp BETWEEN start_timestamp AND end_timestamp
    GROUP BY account_id
),

-- Step 4: Group new accounts into period buckets.
new_holders_per_period AS (
    SELECT
        DATE_TRUNC(period, TO_TIMESTAMP(first_ts / 1000000000.0)) AS period_start,
        COUNT(DISTINCT account_id) AS new_holders
    FROM window_first_hold
    GROUP BY period_start
    ORDER BY period_start
)

-- Step 5: Rolling cumulative total = base + running sum of new accounts per period.
SELECT
    INT8RANGE(
        EXTRACT(EPOCH FROM period_start)::BIGINT * 1000000000,
        COALESCE(
            EXTRACT(EPOCH FROM LEAD(period_start) OVER (ORDER BY period_start))::BIGINT * 1000000000,
            end_timestamp
        )
    ) AS int8range,
    (SELECT base FROM base_holders) +
        SUM(new_holders) OVER (ORDER BY period_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    AS total
FROM new_holders_per_period
ORDER BY period_start;

$$;