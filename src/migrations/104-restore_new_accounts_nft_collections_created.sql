-- 104-restore_new_accounts_nft_collections_created.sql — restores the publishers'
-- definitions of new_accounts and nft_collections_created, replacing 027 and 041.
--
-- 027 and 041 cannot be loaded by any load_metrics_* procedure:
--   1. They RETURN TABLE (timestamp_range int8range, total bigint), but every loader
--      selects the column by its ecosystem.metric_total name:
--        select ..., int8range as timestamp_range, total from ecosystem.%I(...)
--      so each call fails with `column "int8range" does not exist`, which the loaders'
--      per-metric exception handler swallows.
--   2. They close the final (in-progress) period at end_timestamp + 1 instead of
--      leaving its upper bound NULL, so the loaders' `upper(int8range) is not null`
--      filter would store partial periods, and a new row for the same partial period
--      on every run (the upper bound moves each time).
--   3. They convert nanoseconds through float (to_timestamp(ts / 1e9)) instead of
--      timestamp9.
-- 027 also added a key filter (excluding accounts with no key or an empty key list)
-- that the documented methodology ("accounts created within the period, by creation
-- timestamp") does not describe and the live data has never used.
--
-- The bodies below are the mainnet publisher's, identical on the testnet publisher —
-- the definitions every stored new_accounts / nft_collections_created row was
-- computed with. Applying this to a publisher is a no-op. CREATE OR REPLACE cannot
-- change a return type, hence DROP + CREATE; nothing references either function
-- statically (the loaders call them through dynamic SQL).

BEGIN;

DROP FUNCTION IF EXISTS ecosystem.new_accounts(text, bigint, bigint);
DROP FUNCTION IF EXISTS ecosystem.nft_collections_created(text, bigint, bigint);

CREATE FUNCTION ecosystem.new_accounts(period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$

with all_entries as (
  select created_timestamp
  from entity
  where type = 'ACCOUNT'
  and created_timestamp between start_timestamp and end_timestamp
),
accounts_per_period as (
  select date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
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

CREATE FUNCTION ecosystem.nft_collections_created(period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$

with nft_collection as (
  select *
  from token
  where created_timestamp between start_timestamp and end_timestamp
  and type = 'NON_FUNGIBLE_UNIQUE'
  group  by 1
  order by 1 desc
),
created_nft_collection as (
  select date_trunc(period, nft_collection.created_timestamp::timestamp9::timestamp) as period_start_timestamp,
  count(distinct nft_collection.token_id) as total
  from nft_collection
  group by 1
)

select
int8range(
  period_start_timestamp::timestamp9::bigint,
  (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
),
created_nft_collection.total

from created_nft_collection

$$;

COMMIT;
