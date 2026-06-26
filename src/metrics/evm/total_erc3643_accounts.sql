-- Total accounts holding ERC-3643 tokens
-- Rolling total of unique accounts holding an ERC-3643 token with a positive balance

CREATE OR REPLACE FUNCTION ecosystem.total_erc3643_accounts(
    period text,
    start_timestamp bigint DEFAULT 0,
    end_timestamp bigint DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000000000)::bigint
)
RETURNS SETOF ecosystem.metric_total
LANGUAGE sql STABLE
AS $$

WITH
-- One row per holder: the first time the account associated with any ERC-3643
-- (T-REX security token) it currently holds with a positive balance. ERC-3643
-- is indexed through the standard token_account path, so holders are sourced
-- from erc.token_account. There are no ERC-3643 tokens on mainnet yet, so this
-- returns an empty set until one is deployed and erc-sync classifies it.
holder_first_association AS (
    SELECT
        ta.account_id,
        MIN(ta.created_timestamp) AS first_association_timestamp
    FROM erc.token_account ta
    JOIN erc.token t USING (token_id)
    WHERE t.contract_type = 'ERC_3643'
      AND ta.balance > 0
      AND ta.created_timestamp IS NOT NULL
    GROUP BY ta.account_id
),

-- Count holders associated before the window starts (baseline)
base_holders AS (
    SELECT COUNT(*) AS base
    FROM holder_first_association
    WHERE first_association_timestamp < start_timestamp
),

-- Aggregate new holders by period
new_holders_per_period AS (
    SELECT
        DATE_TRUNC(
            period,
            to_timestamp(first_association_timestamp / 1000000000.0)
        ) as period_start_timestamp,
        COUNT(*) as new_holders
    FROM holder_first_association
    WHERE first_association_timestamp BETWEEN start_timestamp AND end_timestamp
    GROUP BY period_start_timestamp
    ORDER BY period_start_timestamp
)

-- Calculate rolling total: base + cumulative new holders
SELECT
    int8range(
        EXTRACT(EPOCH FROM period_start_timestamp)::bigint * 1000000000,
        EXTRACT(EPOCH FROM LEAD(period_start_timestamp) OVER (ORDER BY period_start_timestamp))::bigint * 1000000000
    ) as int8range,
    (SELECT base FROM base_holders) +
        SUM(new_holders) OVER (ORDER BY period_start_timestamp ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as total
FROM new_holders_per_period
ORDER BY period_start_timestamp;

$$;
