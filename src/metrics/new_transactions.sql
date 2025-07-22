create or replace function ecosystem.new_transactions(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default current_timestamp::timestamp9::bigint
) returns setof ecosystem.metric_total
language sql stable
as $$
with transactions_per_period as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
        count(*) as total
    from transaction
    where consensus_timestamp between start_timestamp and end_timestamp
    group by 1
    order by 1 asc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (lead(period_start_timestamp) over (
            order by period_start_timestamp rows between current row and 1 following
        ))::timestamp9::bigint
    ),
    total
from transactions_per_period
$$;
