create or replace function ecosystem.network_tps(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
as $$

with transaction_volume as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
        count(*) as total
    from transaction
    where consensus_timestamp between start_timestamp and end_timestamp
    group by period_start_timestamp
),
network_tps as (
    select
        period_start_timestamp,
        total::float / extract(epoch from CAST('1 ' || 
            CASE 
                WHEN period = 'quarter' THEN 'month' 
                ELSE period 
            END AS Interval) * 
            CASE 
                WHEN period = 'quarter' THEN 3 
                ELSE 1 
            END) as tps
    from transaction_volume
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        coalesce((lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint, end_timestamp)
    ),
    tps::bigint as total
from network_tps

$$ language sql stable;
