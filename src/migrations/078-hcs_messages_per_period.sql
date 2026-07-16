-- 078-hcs_messages_per_period.sql — per-period HCS topic message counts
-- Moved from the legacy ecosystem schema; tracked in Hasura.

BEGIN;

---------------------------------
-- hcs_messages_per_period
---------------------------------
create or replace function ecosystem.hcs_messages_per_period (
    entity_ids entity_id[],
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric
language sql stable
as $$

with messages as (
	select consensus_timestamp::timestamp9::timestamp
	from public.topic_message
		where topic_id = any(entity_ids)
		and consensus_timestamp between start_timestamp and end_timestamp
),
messages_per_period as (
	select
	date_trunc(period, consensus_timestamp) as period_start_timestamp,
	count(consensus_timestamp) as total
	from messages
	group by 1
)

select
  'hcs_messages_per_period' as name,
	period,
	int8range(
		period_start_timestamp::timestamp9::bigint,
		(lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
	) as timestamp_range,
	messages_per_period.total
from messages_per_period

$$;

COMMIT;
