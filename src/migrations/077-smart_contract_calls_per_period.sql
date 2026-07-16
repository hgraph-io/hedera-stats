-- 077-smart_contract_calls_per_period.sql — per-period smart contract call counts
-- Moved from the legacy ecosystem schema; tracked in Hasura.

BEGIN;

---------------------------------
-- smart_contract_calls_per_period
---------------------------------
create or replace function ecosystem.smart_contract_calls_per_period (
    contract_ids bigint[],
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric
language sql stable
as $$

-- contract calls per specified period
with smart_contract_results as (
	select consensus_timestamp::timestamp9::timestamp from public.contract_result
		where contract_id = any(contract_ids)
		and consensus_timestamp between start_timestamp and end_timestamp
),
-- count of smart contract calls per specified period
smart_contract_calls_per_period as (
	select
	date_trunc(period, consensus_timestamp) as period_start_timestamp,
	count(consensus_timestamp) as total
	from smart_contract_results
	group by 1
)

select
	'smart_contract_calls_per_period' as name,
	period,
	int8range(
		period_start_timestamp::timestamp9::bigint,
		(lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
	) as timestamp_range,
	total
from smart_contract_calls_per_period

$$;

COMMIT;
