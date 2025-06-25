create or replace function ecosystem.total_ecdsa_accounts(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default current_timestamp::timestamp9::bigint
) returns setof ecosystem.metric_total
language sql stable
as $$
with base_total as (
  -- Count ECDSA accounts created before the start
  select count(*)::bigint as base
  from (
    select distinct on (num) num
    from entity
    where type = 'ACCOUNT'
      and (public_key like '02%' or public_key like '03%')
      and created_timestamp < start_timestamp
    order by num, created_timestamp
  ) t
),
all_entries as (
  select distinct on (num)
    created_timestamp
  from entity
  where type = 'ACCOUNT'
    and created_timestamp between start_timestamp and end_timestamp
    and (public_key like '02%' or public_key like '03%')
  order by num, created_timestamp
),
accounts_per_period as (
  select
    date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
    count(*) as total_ecdsa_accounts
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
    + sum(total_ecdsa_accounts) over (order by period_start_timestamp) as total
from accounts_per_period
order by period_start_timestamp;
$$;
