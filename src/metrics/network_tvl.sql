create or replace function ecosystem.network_tvl(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
as $$
with defillama_data as (
    select content::jsonb as content
    from http_get('https://api.llama.fi/v2/historicalChainTvl/Hedera')
),
tvl_data as (
    select
        (jsonb_array_elements(content) ->> 'date')::bigint as date_sec,
        (jsonb_array_elements(content) ->> 'tvl')::numeric as tvl
    from defillama_data
),
avg_in_period as (
    select
        date_trunc(period, to_timestamp(date_sec)) as period_start_timestamp,
        avg(tvl)::bigint as avg_tvl
    from tvl_data
    where date_sec between (start_timestamp / 1000000000)
                      and (end_timestamp   / 1000000000)
    group by 1
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
    ) as timestamp_range,
    avg_tvl::bigint as total
from avg_in_period
order by period_start_timestamp
$$ language sql stable;
