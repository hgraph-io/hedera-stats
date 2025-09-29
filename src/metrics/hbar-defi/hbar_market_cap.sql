-- =====================================================
-- HBAR Market Capitalization Metric
-- =====================================================
-- Purpose: Calculate HBAR market cap by multiplying price by circulating supply
--
-- Context:
--   - Market Cap = Price × Circulating Supply
--   - Uses existing metrics: avg_usd_conversion and hbar_total_released
--   - No need to recalculate from raw data - leverages validated metrics
--
-- Implementation:
--   - Joins avg_usd_conversion (price × 100,000) with hbar_total_released (tinybars)
--   - Formula: (price_x100000 × supply_tinybars) / 100,000,000,000
--   - Returns market cap in cents (× 100) for precision
--   - To get USD: divide result by 100
--
-- Dependencies:
--   - Requires ecosystem.avg_usd_conversion metric to exist for the period
--   - Requires ecosystem.hbar_total_released metric to exist for the period
--
-- Usage:
--   Called by job procedures (hourly, daily, weekly, monthly, etc.)
--   Results stored in ecosystem.metric table
-- =====================================================

create or replace function ecosystem.hbar_market_cap(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default current_timestamp::timestamp9::bigint
)
returns setof ecosystem.metric_total
language sql stable
as $$
select
    p.timestamp_range,
    -- Market cap in cents: (price_x100000 × supply_tinybars) / 100,000,000,000
    round((p.total::numeric * s.total::numeric) / 100000000000)::bigint as total
from ecosystem.metric p
join ecosystem.metric s on
    p.timestamp_range = s.timestamp_range and
    p.period = s.period
where p.name = 'avg_usd_conversion'
  and s.name = 'hbar_total_released'
  and p.period = $1  -- Use positional parameter to avoid ambiguity
  and upper(p.timestamp_range) between $2 and $3
order by p.timestamp_range;
$$;
