create or replace function ecosystem.total_transactions(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default current_timestamp::timestamp9::bigint
) returns setof ecosystem.metric_total
language sql stable
as $$
with base_total as (
    select count(*)::bigint as base
    from transaction
    where consensus_timestamp < start_timestamp
),
all_entries as (
    select consensus_timestamp
    from transaction
    where consensus_timestamp between start_timestamp and end_timestamp
),
transactions_per_period as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
        count(*) as total_transactions
    from all_entries
    group by 1
    order by 1 asc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        lead(period_start_timestamp) over (
            order by period_start_timestamp
        )::timestamp9::bigint
    ) as timestamp_range,
    (select base from base_total)
        + sum(total_transactions) over (order by period_start_timestamp) as total
from transactions_per_period
order by period_start_timestamp;
$$;
