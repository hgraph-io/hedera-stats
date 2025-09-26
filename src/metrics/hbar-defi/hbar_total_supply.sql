-- =====================================================
-- HBAR Total Supply Metric
-- =====================================================
-- Purpose: Insert the total HBAR supply (50 billion) into ecosystem.metric table
--
-- Context:
--   - Hedera pre-minted exactly 50 billion HBAR at network genesis
--   - This value is hardcoded in the Mirror Node (NetworkSupplyViewModel.totalSupply)
--   - The total supply cannot change without unanimous consent of the Hedera Council
--   - Note: Summing all entity balances yields 49,999,943,600 HBAR (missing 56,400 HBAR)
--           The missing amount appears to exist at protocol level, outside any account
--
-- Implementation:
--   - Creates 7 rows (one per time period) for user query flexibility
--   - Users can query with any period (minute, hour, day, week, month, year)
--   - Ideally users do not use a period when querying
--   - Timestamp range represents validity period (genesis to future date)
--   - Upper bound can be interpreted as "last verified"
--
-- Usage:
--   Run this INSERT to populate/update the metric
--   Query with: SELECT total FROM ecosystem.metric WHERE name = 'hbar_total_supply' AND period = 'day'
-- =====================================================

WITH supply AS (
    SELECT
        5000000000000000000 AS total,  -- 50 billion HBAR in tinybars (1 HBAR = 100,000,000 tinybars)
        '[1567296000000000000, 2000000000000000000)'::int8range AS range  -- Sept 1, 2019 (genesis)
)
INSERT INTO ecosystem.metric (name, period, timestamp_range, total)
SELECT
    'hbar_total_supply' AS name,
    p.period,
    s.range,
    s.total
FROM supply s
CROSS JOIN (VALUES
    ('minute'),   -- Minute granularity
    ('hour'),     -- Hour granularity
    ('day'),      -- Day granularity (most common)
    ('week'),     -- Week granularity
    ('month'),    -- Month granularity
    ('quarter'),  -- Year granularity
    ('year')      -- Year granularity
) AS p(period)
ON CONFLICT (name, period, timestamp_range)
DO UPDATE SET total = EXCLUDED.total;  -- Ensures idempotency: safe to run multiple times

-- =====================================================
-- Test Query
-- =====================================================
-- To verify the insert and get total supply in different units:

-- SELECT
--     total AS total_tinybars,
--     total / 100000000.0 AS total_hbar,
--     total / 100000000.0 / 1000000000.0 AS total_billion_hbar
-- FROM ecosystem.metric
-- WHERE name = 'hbar_total_supply'
-- LIMIT 1;

-- Expected result: 50.0 billion HBAR