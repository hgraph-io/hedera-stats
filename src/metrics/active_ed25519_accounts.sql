create or replace function ecosystem.active_ed25519_accounts(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default current_timestamp::timestamp9::bigint
)
returns setof ecosystem . metric_total
as $$
with ed25519_transactions as (
    select
        t.consensus_timestamp,
        t.payer_account_id
    from transaction t
    join entity e
        on t.payer_account_id = e.id
    where t.consensus_timestamp between start_timestamp and end_timestamp
        and e.type = 'ACCOUNT'
        and e.key is not null
        and e.created_timestamp is not null
        and substring(e.key from 1 for 2) = e'\\x1220'
),
ed25519_accounts_per_period as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
        count(distinct payer_account_id) as total
    from ed25519_transactions
    group by 1
    order by 1 desc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
    ),
    total
from ed25519_accounts_per_period
$$ language sql stable;
