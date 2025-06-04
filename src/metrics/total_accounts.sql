create or replace function ecosystem.total_accounts(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

with all_entries as (
  select created_timestamp
  from entity
  where type = 'ACCOUNT'
    and created_timestamp between start_timestamp and end_timestamp
),
accounts_per_period as (
  select
    date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
    count(*) as accounts_created
  from all_entries
  group by 1
),
total_accounts as (
  select
    period_start_timestamp,
    sum(accounts_created) over (order by period_start_timestamp) as total
  from accounts_per_period
)
select
  int8range(
    period_start_timestamp::timestamp9::bigint,
    (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
  ) as timestamp_range,
  total
from total_accounts

$$;
