create or replace function ecosystem.nft_collection_sales_volume(
  token_id bigint,
  period text default 'century',
  excluded_accounts bigint [] default null,
  start_timestamp bigint default 0,
  end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns ecosystem . metric
language sql stable
as $$

with nft_transfers as (
  select upper(timestamp_range) as end_consensus_timestamp
  from nft_history
  where nft_history.token_id = nft_collection_sales_volume.token_id
  and upper(timestamp_range) between start_timestamp and end_timestamp
),
nft_transactions as (
  select consensus_timestamp
  from transaction tx
  inner join nft_transfers nt on tx.consensus_timestamp = nt.end_consensus_timestamp
  where tx.type <> 37  -- exclude initial mint
),
hbar_transfers as (
  select amount, tx.consensus_timestamp
  from crypto_transfer as ct
  inner join nft_transactions as tx
  on ct.consensus_timestamp = tx.consensus_timestamp
  where ct.amount > 0
  and (excluded_accounts is null
    or (ct.entity_id <> ALL(excluded_accounts) and ct.payer_account_id <> ALL(excluded_accounts))
  )
),
nft_hbar_transfers as (
  select
  date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
  sum(amount) as total
  from hbar_transfers
  group by 1
)

select
-- (select name from token where token_id = nft_collection_sales_volume.token_id limit 1) || ' sales volume' as name,
'collection_' || token_id::text || '_sales_volume' as name,
period,
int8range(
  period_start_timestamp::timestamp9::bigint,
  (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
) as timestamp_range,
nft_hbar_transfers.total
from nft_hbar_transfers

$$;
