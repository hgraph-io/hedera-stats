-- Total accounts holding ERC-20 tokens
-- Rolling total of unique EVM addresses that have received ERC-20 tokens

CREATE OR REPLACE FUNCTION ecosystem.total_erc20_accounts(
    period text,
    start_timestamp bigint DEFAULT 0,
    end_timestamp bigint DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000000000)::bigint
)
RETURNS SETOF ecosystem.metric_total
LANGUAGE sql STABLE
AS $$

WITH
-- Count holders before the window starts (baseline). Sourced from the erc
-- indexer's token_transfer table, filtered to ERC-20 receipts (transfer/mint).
-- The zero address is excluded as it represents burns.
base_holders AS (
    SELECT COUNT(DISTINCT receiver_evm_address) AS base
    FROM erc.token_transfer
    WHERE contract_type = 'ERC_20'
      AND transfer_type IN ('transfer', 'mint')
      AND receiver_evm_address IS NOT NULL
      AND receiver_evm_address != '0x0000000000000000000000000000000000000000'
      AND consensus_timestamp < start_timestamp
),

-- Identify the first receipt timestamp for each address within the window
first_receipt_per_holder AS (
    SELECT
        receiver_evm_address AS holder_address,
        MIN(consensus_timestamp) AS first_receipt_timestamp
    FROM erc.token_transfer
    WHERE contract_type = 'ERC_20'
      AND transfer_type IN ('transfer', 'mint')
      AND receiver_evm_address IS NOT NULL
      AND receiver_evm_address != '0x0000000000000000000000000000000000000000'
      AND consensus_timestamp BETWEEN start_timestamp AND end_timestamp
    GROUP BY receiver_evm_address
),

-- Aggregate new holders by period
new_holders_per_period AS (
    SELECT
        DATE_TRUNC(
            period,
            to_timestamp(first_receipt_timestamp / 1000000000.0)
        ) as period_start_timestamp,
        COUNT(DISTINCT holder_address) as new_holders
    FROM first_receipt_per_holder
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
