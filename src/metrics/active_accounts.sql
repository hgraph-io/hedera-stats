create or replace function ecosystem.active_accounts(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
as $$
with active_accounts as (
  select *
    from ecosystem.active_developer_accounts(period, start_timestamp, end_timestamp)
  union all select *
    from ecosystem.active_retail_accounts(period, start_timestamp, end_timestamp)
  union all select *
    from ecosystem.active_smart_contracts(period, start_timestamp, end_timestamp)
),
merged_data as (
    select lower(int8range) as period_start_timestamp, sum(total) as total
  from active_accounts d
  group by 1
  order by 1 desc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        coalesce((lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint, end_timestamp)
    ),
    total
from merged_data
$$ language sql stable;
