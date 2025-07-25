create or replace function ecosystem.new_smart_contracts(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default current_timestamp::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$
with all_entries as (
    select
        e.created_timestamp
    from entity e
    join transaction t
        on e.created_timestamp = t.consensus_timestamp
    where e.type = 'CONTRACT'
        and t.type = 8    -- CONTRACTCREATEINSTANCE
        and t.result = 22 -- SUCCESS
        and e.created_timestamp between start_timestamp and end_timestamp
),
contracts_per_period as (
    select
        date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
        count(*) as total
    from all_entries
    group by 1
    order by 1 asc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
    ),
    total
from contracts_per_period
$$;
