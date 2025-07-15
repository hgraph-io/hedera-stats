create or replace function ecosystem.current_nft_market_cap()
returns setof ecosystem . metric_total
language sql stable
as $$

with latest_sale_per_nft as (
  select distinct on (token_id, serial_number) timestamp_range
  from nft_history
  -- remove minting transactions
  where spender is not null
  -- most recent sale
  order by token_id, serial_number, upper(timestamp_range) desc

),
nft_hbar_transfers as (
  select amount, consensus_timestamp
  from latest_sale_per_nft as ls
  left join crypto_transfer as ct
  on ct.consensus_timestamp = upper(ls.timestamp_range)
  where ct.amount > 0

)

select
int8range(0, CURRENT_TIMESTAMP::timestamp9::bigint) as timestamp_range,
sum(amount) as total
from nft_hbar_transfers

$$;
