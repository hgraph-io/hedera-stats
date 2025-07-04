create or replace function ecosystem.new_ed25519_accounts(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem.metric_total
as $$
with all_entries as (
    select
        e.id,
        e.created_timestamp
    from entity e
    where e.type = 'ACCOUNT'
      and e.key is not null
      and substring(e.key from 1 for 2) = e'\\x1220'
      and e.created_timestamp between start_timestamp and end_timestamp
),
accounts_per_period as (
    select
        date_trunc(period, to_timestamp(created_timestamp / 1e9)) as period_start_timestamp,
        count(*) as total
    from all_entries
    group by 1
    order by 1 asc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        lead(period_start_timestamp)
            over (order by period_start_timestamp rows between current row and 1 following)
            ::timestamp9::bigint
    ) as timestamp_range,
    total
from accounts_per_period
$$ language sql stable;
