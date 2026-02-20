-- total_erc3643_accounts
-- Total unique accounts holding ERC-3643 (T-REX) security tokens as of each period.
--
-- IDENTIFICATION STRATEGY: Uses T-REX-exclusive event signatures to identify token contracts.
-- Two events exclusive to IERC3643.sol (T-REX spec):
--   ComplianceAdded(address)        topic0: 0x7f3a888862559648ec01d97deb7b5012bff86dc91e654a1de397170db40e35b6
--   IdentityRegistryAdded(address)  topic0: 0xd2be862d755bca7e0d39772b2cab3a5578da9c285f69199f4c063c2294a7f36c
--
CREATE OR REPLACE FUNCTION ecosystem.total_erc3643_accounts(
    period TEXT,
    start_timestamp BIGINT DEFAULT 0,
    end_timestamp BIGINT DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000000000)::BIGINT
)
RETURNS SETOF ecosystem.metric_total
LANGUAGE sql STABLE
AS $$

WITH

-- Step 1: Identify confirmed T-REX token contracts via exclusive event signatures.
-- Restrict contract_log to erc.token IDs first to leverage (contract_id, consensus_timestamp) index.
trex_token_contracts AS (
    SELECT DISTINCT cl.contract_id
    FROM public.contract_log cl
    WHERE cl.contract_id IN (SELECT token_id FROM erc.token)
      AND cl.topic0 IN (
          '\x7f3a888862559648ec01d97deb7b5012bff86dc91e654a1de397170db40e35b6',  -- ComplianceAdded(address)
          '\xd2be862d755bca7e0d39772b2cab3a5578da9c285f69199f4c063c2294a7f36c'   -- IdentityRegistryAdded(address)
      )
),

-- Step 2: Count holders with positive balance who first appeared BEFORE the query window.
base_holders AS (
    SELECT COUNT(DISTINCT account_id) AS base
    FROM erc.token_account
    WHERE token_id IN (SELECT contract_id FROM trex_token_contracts)
      AND balance > 0
      AND created_timestamp < start_timestamp
),

-- Step 3: Per-account earliest first-hold timestamp within the window.
-- MIN() deduplicates accounts holding multiple T-REX tokens.
window_first_hold AS (
    SELECT
        account_id,
        MIN(created_timestamp) AS first_ts
    FROM erc.token_account
    WHERE token_id IN (SELECT contract_id FROM trex_token_contracts)
      AND balance > 0
      AND created_timestamp BETWEEN start_timestamp AND end_timestamp
    GROUP BY account_id
),

-- Step 4: Group new holders by time period bucket.
new_holders_per_period AS (
    SELECT
        DATE_TRUNC(period, TO_TIMESTAMP(first_ts / 1000000000.0)) AS period_start,
        COUNT(DISTINCT account_id) AS new_holders
    FROM window_first_hold
    GROUP BY period_start
    ORDER BY period_start
)

-- Step 5: Rolling cumulative = base + running sum of new holders per period.
SELECT
    INT8RANGE(
        EXTRACT(EPOCH FROM period_start)::BIGINT * 1000000000,
        EXTRACT(EPOCH FROM LEAD(period_start) OVER (ORDER BY period_start))::BIGINT * 1000000000
    ) AS int8range,
    (SELECT base FROM base_holders) +
        SUM(new_holders) OVER (ORDER BY period_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    AS total
FROM new_holders_per_period
ORDER BY period_start;

$$;
