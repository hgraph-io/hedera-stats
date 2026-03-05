-- Total accounts holding ERC-1155 tokens
-- Rolling total of unique addresses that have received ERC-1155 tokens

CREATE OR REPLACE FUNCTION ecosystem.total_erc1155_accounts(
    period text,
    start_timestamp bigint DEFAULT 0,
    end_timestamp bigint DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000000000)::bigint
)
RETURNS SETOF ecosystem.metric_total
LANGUAGE sql STABLE
AS $$

WITH 
-- ERC-1155 event signatures (TransferSingle and TransferBatch)
erc1155_signatures AS (
    SELECT 
        '\xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62'::bytea as transfer_single,
        '\x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb'::bytea as transfer_batch
),

-- Count holders before the window starts (baseline)
base_holders AS (
    SELECT COUNT(DISTINCT holder_address) as base
    FROM (
        SELECT DISTINCT 
            CASE 
                WHEN length(topic3) = 20 THEN '0x' || encode(topic3, 'hex')
                WHEN length(topic3) < 20 THEN '0x' || lpad(encode(topic3, 'hex'), 40, '0')
                ELSE '0x' || encode(substring(topic3 from length(topic3)-19 for 20), 'hex')
            END as holder_address
        FROM contract_log
        CROSS JOIN erc1155_signatures
        WHERE topic0 IN (transfer_single, transfer_batch)
          AND consensus_timestamp < start_timestamp
    ) pre_window
    WHERE holder_address != '0x0000000000000000000000000000000000000000'
),

-- Get all receipt events within the time window
receipt_events AS (
    SELECT 
        consensus_timestamp,
        CASE 
            WHEN length(topic3) = 20 THEN '0x' || encode(topic3, 'hex')
            WHEN length(topic3) < 20 THEN '0x' || lpad(encode(topic3, 'hex'), 40, '0')
            ELSE '0x' || encode(substring(topic3 from length(topic3)-19 for 20), 'hex')
        END as holder_address
    FROM contract_log
    CROSS JOIN erc1155_signatures
    WHERE topic0 IN (transfer_single, transfer_batch)
      AND consensus_timestamp BETWEEN start_timestamp AND end_timestamp
),

-- Identify first receipt timestamp for each address (excluding zero address)
first_receipt_per_holder AS (
    SELECT 
        holder_address,
        MIN(consensus_timestamp) as first_receipt_timestamp
    FROM receipt_events
    WHERE holder_address != '0x0000000000000000000000000000000000000000'
    GROUP BY holder_address
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
