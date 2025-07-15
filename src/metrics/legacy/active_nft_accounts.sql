create or replace function ecosystem.active_nft_accounts(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

with all_nft_entries as (
  select account_id, timestamp_range from nft
  where upper(timestamp_range) between start_timestamp and end_timestamp
  or lower(timestamp_range) between start_timestamp and end_timestamp
  and account_id is not null

  union all

  select account_id, timestamp_range from nft_history
  where upper(timestamp_range) between start_timestamp and end_timestamp
  or lower(timestamp_range) between start_timestamp and end_timestamp
  and account_id is not null
),
all_active_account_actions as (
  -- token associations
  select
  token_account.created_timestamp as consensus_timestamp,
  account_id
  from token_account
  inner join token on token_account.token_id = token.token_id
  where token_account.created_timestamp between start_timestamp and end_timestamp
  and token.type = 'NON_FUNGIBLE_UNIQUE'

  union all

  -- received an nft
  select
  lower(timestamp_range) as consensus_timestamp,
  account_id
  from all_nft_entries

  union all

  -- sent an nft
  select
  upper(timestamp_range) as consensus_timestamp,
  account_id
  from all_nft_entries
),
distinct_account as (
  select date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
  count(distinct account_id) as total
  from all_active_account_actions
  where consensus_timestamp between start_timestamp and end_timestamp
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
