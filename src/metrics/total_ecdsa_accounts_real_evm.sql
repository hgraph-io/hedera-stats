-- Rolling total of ECDSA accounts that have a real (non-derived) EVM address
create or replace function ecosystem.total_ecdsa_accounts_real_evm(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default current_timestamp::timestamp9::bigint
) returns setof ecosystem.metric_total
language sql stable
as $$
with base_total as (
  -- Count qualifying accounts created before the window start
  select count(*)::bigint as base
  from (
    select distinct on (num) num
    from entity
    where type = 'ACCOUNT'
      -- ECDSA secp256k1 compressed pubkeys start with 0x02 or 0x03
      and (public_key like '02%' or public_key like '03%')
      -- has an explicitly set EVM address
      and evm_address is not null
      -- exclude the default zero-prefixed "derived from entity ID" address:
      --   20 bytes = 4B shard || 8B realm || 8B num (big-endian)
      and encode(evm_address, 'hex')
            <> lpad(to_hex(shard), 8, '0')
             || lpad(to_hex(realm), 16, '0')
             || lpad(to_hex(num),   16, '0')
      and created_timestamp < start_timestamp
    order by num, created_timestamp
  ) t
),
all_entries as (
  -- new qualifying accounts within [start, end]
  select distinct on (num)
    created_timestamp
  from entity
  where type = 'ACCOUNT'
    and created_timestamp between start_timestamp and end_timestamp
    and (public_key like '02%' or public_key like '03%')
    and evm_address is not null
    and encode(evm_address, 'hex')
          <> lpad(to_hex(shard), 8, '0')
           || lpad(to_hex(realm), 16, '0')
           || lpad(to_hex(num),   16, '0')
  order by num, created_timestamp
),
accounts_per_period as (
  -- bucket by requested period (hour/day/week/…)
  select
    date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
    count(*) as new_ecdsa_with_real_evm
  from all_entries
  group by 1
  order by 1 asc
)
select
  int8range(
    period_start_timestamp::timestamp9::bigint,
    lead(period_start_timestamp) over (order by period_start_timestamp)::timestamp9::bigint
  ) as timestamp_range,
  (select base from base_total)
    + sum(new_ecdsa_with_real_evm) over (order by period_start_timestamp) as total
from accounts_per_period
order by period_start_timestamp;
$$;
