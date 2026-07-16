-- 081-active_accounts_per_period.sql — per-period distinct active accounts for entities
-- Moved from the legacy ecosystem schema; tracked in Hasura.

BEGIN;

---------------------------------
-- active_accounts_per_period
---------------------------------
create or replace function ecosystem.active_accounts_per_period (
    entity_ids entity_id[],
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric
language sql stable
as $$

-- interacted
with token_transfers as (
	select account_id, consensus_timestamp
	from public.token_transfer
		where token_id = any(entity_ids)
		and consensus_timestamp between start_timestamp and end_timestamp
),
contract_callers as (
	select payer_account_id as account_id, consensus_timestamp
	from public.contract_result
		where contract_id = any(entity_ids)
		and consensus_timestamp between start_timestamp and end_timestamp
),
message_submitters as (
	select payer_account_id as account_id, consensus_timestamp
	from public.topic_message
		where topic_id = any(entity_ids)
		and consensus_timestamp between start_timestamp and end_timestamp
),
distinct_accounts_per_period as (
	select
	date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
	count(distinct account_id) as total
	from (
		select account_id, consensus_timestamp
		from token_transfers
		union
		select account_id, consensus_timestamp
		from contract_callers
		union
		select account_id, consensus_timestamp
		from message_submitters
	)
	group by 1
)

select
  'active_accounts_per_period' as name,
	period,
	int8range(
		period_start_timestamp::timestamp9::bigint,
		(lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
	) as timestamp_range,
	distinct_accounts_per_period.total
from distinct_accounts_per_period

$$;

COMMIT;
