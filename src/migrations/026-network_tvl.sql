-- 026-network_tvl.sql — baseline migration generated from src/jobs/network_tvl.sql.
-- Ordered so every ecosystem.* function it references already exists
-- (applies with check_function_bodies on).

BEGIN;

-----------------------
-- network_tvl
-----------------------
create or replace procedure ecosystem.load_network_tvl()
as $$

  with defillama as (
    select
        (jsonb_array_elements(content) ->> 'date')::numeric as date_sec,
        (jsonb_array_elements(content) ->> 'tvl')::numeric as tvl
    from (
      select content::jsonb as content
      from http_get('https://api.llama.fi/v2/historicalChainTvl/Hedera')
    )
  ),
  transformed as (
    select
      -- DeFiLlama timestamps are midnight UTC; forward range ensures row
      -- is labeled with the same calendar day
      int8range(
        (to_timestamp(date_sec))::timestamp9::bigint,
        (to_timestamp(date_sec) + '1 day'::interval)::timestamp9::bigint
      ) as timestamp_range,
    tvl
    from defillama
  )

  insert into ecosystem.metric (name, period, timestamp_range, total)
  select 'network_tvl', 'day', timestamp_range, tvl
  from transformed
  on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;

$$ language sql;

COMMIT;
