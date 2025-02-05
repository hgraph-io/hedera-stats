create or replace function ecosystem.stablecoin_marketcap(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default current_timestamp::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$
with defillama_data as (
    select content::jsonb as content
    from http_get('https://stablecoins.llama.fi/stablecoincharts/Hedera')
),
raw_data as (
    -- “Expand” JSON array -> each row = element of elem array
    -- elem->>>'date' = Unix time (sec), elem->'totalCirculatingUSD' = object with peggedUSD, peggedCHF, etc.
    -- Use CROSS JOIN LATERAL to pull all values from the object (peggedUSD, peggedCHF, ...) and summarize.
    select
        (elem->>'date')::bigint as date_sec,
        sum((kv.value)::numeric) as marketcap
    from defillama_data
         cross join lateral jsonb_array_elements(content) as elem
         cross join lateral jsonb_each(elem->'totalCirculatingUSD') kv
    group by 1
),
avg_in_period as (
    select
        date_trunc(period, to_timestamp(date_sec)) as period_start_timestamp,
        avg(marketcap)::bigint as avg_marketcap
    from raw_data
    where date_sec between (start_timestamp / 1000000000)
                      and (end_timestamp   / 1000000000)
    group by 1
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
    ) as timestamp_range,
    avg_marketcap::bigint as total
from avg_in_period
order by period_start_timestamp

$$;
