-- =====================================================
-- HBAR Released Supply Metric
-- =====================================================
-- Purpose: Track the circulating (released) supply of HBAR over time
--
-- Context:
--   - Total supply: 50 billion HBAR (5,000,000,000,000,000,000 tinybars)
--     Pre-minted at network genesis (Aug 24, 2018)
--   - Mirror node data begins: Sept 13, 2019 22:00 UTC with ~3.52B HBAR already released
--   - Released supply: Pre-mirror distributions plus net treasury flows since Sept 2019
--   - Tracks cumulative net flows from 548 designated treasury/system accounts
--
-- Implementation:
--   - Uses crypto_transfer table to track treasury flows from Sept 13, 2019 22:00 UTC
--   - Formula: Released Supply = Calibration Constant - Cumulative Treasury Flows
--   - Negative amounts in crypto_transfer = outflows from treasury = increases released
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
-- Flow:
-- Step 1: Calculate net flows from ALL treasury accounts per period
--      Flows are aggregated by period (day, week, month, etc.)
-- Step 2: Calculate cumulative released supply over time
--      Starting with calibration constant (~3.52B HBAR pre-mirror), subtract cumulative flows
--      Subtracting negative outflows increases released, subtracting positive inflows decreases it
-- Step 3: Format results with proper timestamp ranges
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
treasury_flows as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start,
        coalesce(sum(amount), 0) as period_flow  -- Negative = outflow (release), Positive = inflow
    from crypto_transfer
    where consensus_timestamp between 0 and end_timestamp  -- Always calculate from beginning for cumulative accuracy
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
cumulative_released as (
    select
        period_start,
        -- Calibration constant (351871530222399283) minus cumulative flows - accounts for ~3.52B HBAR distributed before mirror node
        351871530222399283 - sum(period_flow) over (order by period_start) as total
    from treasury_flows
    order by period_start
)
select
    int8range(
        period_start::timestamp9::bigint,
        coalesce(
            lead(period_start) over (order by period_start)::timestamp9::bigint,
            end_timestamp  -- Use consistent timestamp boundaries
        )
    ) as timestamp_range,
    total
from cumulative_released
where date_trunc(period, period_start::timestamp9::timestamp) >=
      date_trunc(period, start_timestamp::timestamp9::timestamp)  -- Filter results after calculating full cumulative sum
order by period_start;
$$;
