create or replace function ecosystem.active_retail_accounts(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
as $$
with accounts_transactions as (
    select
        t.consensus_timestamp,
        t.payer_account_id,
        t.type
    from transaction t
    join entity e on t.payer_account_id = e.id
    where e.type != 'CONTRACT' -- not smart contracts
    and t.result = 22 -- Success result
    and t.consensus_timestamp between start_timestamp and end_timestamp
),
excluded_accounts as (
    select payer_account_id
    from accounts_transactions
    where type in (8, 9, 29, 36, 37, 58, 24, 25)
    group by payer_account_id
),
retail_transactions as (
    select atx.consensus_timestamp, atx.payer_account_id
    from accounts_transactions atx
    left join excluded_accounts ex
           on atx.payer_account_id = ex.payer_account_id
    where ex.payer_account_id is null
),
retail_accounts_per_period as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
        count(distinct payer_account_id) as total
    from retail_transactions
    group by 1
    order by 1 desc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
    ),
    total
from retail_accounts_per_period
$$ language sql stable;
