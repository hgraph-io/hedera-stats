-- 097-active_nft_builder_accounts.sql — active_nft_builder_accounts metric: distinct accounts creating or minting NFTs per period.
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

CREATE OR REPLACE FUNCTION ecosystem.active_nft_builder_accounts(period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$

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

COMMIT;
