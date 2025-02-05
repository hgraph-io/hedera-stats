create or replace function ecosystem.account_growth(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$
with retail_created_accounts as (
    select
        id,
        created_timestamp
    from entity
    where type != 'CONTRACT' -- not smart contracts
    and created_timestamp between start_timestamp and end_timestamp
    and not exists (
        select 1
        from transaction t
        where
            entity.id = t.payer_account_id
            and type in (8, 9, 29, 36, 37, 58, 24, 25) -- no developer transactions
    )
),
retail_created_accounts_per_period as (
    select
        date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
        count(distinct id) as total
    from retail_created_accounts
    group by 1
    order by 1 desc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
    ),
    total
from retail_created_accounts_per_period

$$;

