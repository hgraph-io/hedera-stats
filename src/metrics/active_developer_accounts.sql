create or replace function ecosystem.active_developer_accounts(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
as $$
with developer_transactions as (
    select
        t.consensus_timestamp,
        t.payer_account_id
    from transaction t
    join entity e on t.payer_account_id = e.id
    where t.result = 22 -- success result
    and e.type != 'CONTRACT' -- not smart contracts
	and t.type in (8, 9, 29, 36, 37, 58, 24, 25) -- Smart Contract Create / Update Transaction, Token Create / Update / Mint (FT & NFT) Transaction / TokenAirdrop, Create / Update Topic Transaction
    and t.consensus_timestamp between start_timestamp and end_timestamp
),
developer_accounts_per_period as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
        count(distinct payer_account_id) as total
    from developer_transactions
    group by 1
    order by 1 desc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
    ),
    total
from developer_accounts_per_period
$$ language sql stable;
