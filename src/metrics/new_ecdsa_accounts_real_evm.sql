create or replace function ecosystem.new_ecdsa_accounts_real_evm(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default current_timestamp::timestamp9::bigint
)
returns setof ecosystem.metric_total
language sql stable
as $$
with all_entries as (
    select
        e.id,
        e.created_timestamp
    from entity e
    where e.type = 'ACCOUNT'
        and e.key is not null
        and e.created_timestamp is not null
        and (
            e.public_key like '02%'
            or e.public_key like '03%'
        )
        and e.evm_address is not null
        and encode(e.evm_address, 'hex')
              <> lpad(to_hex(e.shard), 8, '0')
               || lpad(to_hex(e.realm), 16, '0')
               || lpad(to_hex(e.num),   16, '0')
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
        (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
    ),
    total
from accounts_per_period
$$;