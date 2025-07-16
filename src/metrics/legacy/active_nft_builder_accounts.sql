create or replace function ecosystem.active_nft_builder_accounts(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

with all_nft_entries as (
  select account_id, created_timestamp from nft
  where created_timestamp between start_timestamp and end_timestamp
  and account_id is not null

  union all

  select account_id, created_timestamp from nft_history
  where created_timestamp between start_timestamp and end_timestamp
  and account_id is not null
),

all_active_creator_account_actions as (
  -- created new NFT collection
  select
  created_timestamp,
  treasury_account_id as account_id
  from token
  where created_timestamp between start_timestamp and end_timestamp
  and type = 'NON_FUNGIBLE_UNIQUE'

  union all

  -- minted NFT
  select
  created_timestamp,
  account_id
  from all_nft_entries

),
distinct_account as (
  select date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
  count(distinct account_id) as total
  from all_active_creator_account_actions
  group by 1
  order by 1 desc
)


select
int8range(
  period_start_timestamp::timestamp9::bigint,
  (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
),
total

from distinct_account

$$;
