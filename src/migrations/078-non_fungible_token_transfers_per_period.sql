-- 078-non_fungible_token_transfers_per_period.sql — per-period NFT transfer counts
-- Moved from the legacy ecosystem schema; tracked in Hasura.

BEGIN;

---------------------------------
-- non_fungible_token_transfers_per_period
---------------------------------
create or replace function ecosystem.non_fungible_token_transfers_per_period (
    token_ids entity_id[],
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric
language sql stable
as $$

with token_transfers as (
	select consensus_timestamp::timestamp9::timestamp
	from public.nft_transfer
		where token_id = any(token_ids)
		and consensus_timestamp between start_timestamp and end_timestamp
),
-- count of transactions per specified period
transfers as (
	select
	date_trunc(period, consensus_timestamp) as period_start_timestamp,
	count(consensus_timestamp) as total
	from token_transfers
	group by 1
)

select
  'non_fungible_token_transfers_per_period' as name,
	period,
	int8range(
		period_start_timestamp::timestamp9::bigint,
		(lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
	) as timestamp_range,
	transfers.total
from transfers

$$;

COMMIT;
