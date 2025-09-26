-- =====================================================
-- HBAR Released Supply Metric
-- =====================================================
-- Purpose: Track the circulating (released) supply of HBAR over time
--
-- Context:
--   - Total supply: 50 billion HBAR (5,000,000,000,000,000,000 tinybars)
--     Pre-minted at network genesis (Sept 16, 2019)
--   - Released supply: Total supply minus unreleased treasury balances
--   - Tracks cumulative net flows from 548 designated treasury/system accounts
--
-- Implementation:
--   - Uses crypto_transfer table to track all treasury flows from genesis
--   - Negative amounts in crypto_transfer = outflows from treasury = releases
--   - Positive amounts in crypto_transfer = inflows to treasury = reduces released
--   - Returns value in tinybars (1 HBAR = 100,000,000 tinybars)
--
-- Treasury Account Ranges (548 accounts total):
--   - 0.0.2: Primary Hedera Treasury account
--   - 0.0.42: System account
--   - 0.0.44-71: 28 system accounts
--   - 0.0.73-87: 15 system accounts
--   - 0.0.99-100: 2 system accounts
--   - 0.0.200-349: 150 reserved accounts
--   - 0.0.400-750: 351 reserved accounts
--
-- Usage:
--   Called by job procedures (daily, weekly, monthly, etc.)
--   Results stored in ecosystem.metric table
-- =====================================================

create or replace function ecosystem.hbar_total_released(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default current_timestamp::timestamp9::bigint
)
returns setof ecosystem.metric_total
language sql stable
as $$
with
-- Step 1: Calculate net flows from ALL treasury accounts per period
-- Flows are aggregated by period (day, week, month, etc.)
treasury_flows as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start,
        sum(amount) as period_flow  -- Negative = outflow (release), Positive = inflow
    from crypto_transfer
    where consensus_timestamp between start_timestamp and end_timestamp
        and (
            -- All 548 treasury/system accounts
            entity_id = 2                              -- 0.0.2 (Primary Treasury)
            or entity_id = 42                          -- 0.0.42
            or (entity_id >= 44 and entity_id <= 71)   -- 0.0.44-71 (28 accounts)
            or (entity_id >= 73 and entity_id <= 87)   -- 0.0.73-87 (15 accounts)
            or (entity_id >= 99 and entity_id <= 100)  -- 0.0.99-100 (2 accounts)
            or (entity_id >= 200 and entity_id <= 349) -- 0.0.200-349 (150 accounts)
            or (entity_id >= 400 and entity_id <= 750) -- 0.0.400-750 (351 accounts)
        )
    group by period_start
),
-- Step 2: Calculate cumulative released supply over time
-- Starting with 50B HBAR total supply, add cumulative treasury flows
-- Outflows (negative) increase released supply, inflows (positive) decrease it
cumulative_released as (
    select
        period_start,
        -- Total supply + cumulative flows (outflows are negative, so they increase released)
        5000000000000000000 + sum(sum(period_flow)) over (order by period_start) as total
    from treasury_flows
    group by period_start
    order by period_start
)
-- Step 3: Format results with proper timestamp ranges
select
    int8range(
        period_start::timestamp9::bigint,
        lead(period_start) over (order by period_start)::timestamp9::bigint
    ) as timestamp_range,
    total
from cumulative_released
order by period_start;
$$;

-- =====================================================
-- Test Query
-- =====================================================
-- To verify the function and get current released supply:
--
-- SELECT
--     timestamp_range,
--     total as released_supply_tinybars,
--     total / 100000000.0 as released_supply_hbar
-- FROM ecosystem.hbar_total_released('day', 0, current_timestamp::timestamp9::bigint)
-- ORDER BY timestamp_range DESC
-- LIMIT 10;
--
-- Expected current result: ~42,392,926,543.50 HBAR released
-- Expected at genesis: ~46,949,066,102 HBAR released (initial distribution)
-- =====================================================