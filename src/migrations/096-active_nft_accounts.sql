-- 096-active_nft_accounts.sql — active_nft_accounts metric: distinct accounts with any NFT activity per period.
--
-- Promoted from the publishers, where this function existed with no migration
-- (identical on the mainnet and testnet publishers unless noted below).
-- Body copied verbatim from the mainnet publisher's definition so that
-- applying it there is a no-op; behaviour changes belong in later migrations.
--
-- Reads mirror-node tables; on the publishers it is driven by the legacy
-- load_metrics / load_hourly_metrics loaders. Grants come from 082's
-- ALTER DEFAULT PRIVILEGES.

BEGIN;

CREATE OR REPLACE FUNCTION ecosystem.active_nft_accounts(period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$

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

COMMIT;
