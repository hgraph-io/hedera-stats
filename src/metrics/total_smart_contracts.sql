create or replace function ecosystem.total_smart_contracts(
    period text,
    start_timestamp bigint default 0,
    end_timestamp   bigint default (current_timestamp)::timestamp9::bigint
) returns setof ecosystem.metric_total
language sql stable
as $$
  -- Count smart contracts created before the start
with base_total as (
    select count(*)::bigint as base
    from   entity
    where  type = 'CONTRACT'
      and  created_timestamp < start_timestamp
),
all_entries as (
    select created_timestamp
    from   entity
    where  type = 'CONTRACT'
      and  created_timestamp between start_timestamp and end_timestamp
),
accounts_per_period as (
    select date_trunc(
               period, created_timestamp::timestamp9::timestamp
           )                                as period_start_timestamp,
           count(*)                         as smart_contracts_in_period
    from   all_entries
    group  by 1
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        lead(period_start_timestamp) over (order by period_start_timestamp)
             ::timestamp9::bigint
    )                                   as timestamp_range,

    (select base from base_total)
    + sum(smart_contracts_in_period)
          over (order by period_start_timestamp)
        as total
from accounts_per_period
order by period_start_timestamp;
$$;
