-- 075-transaction_fees_per_period.sql — per-period charged fees for payer accounts
-- Moved from the legacy ecosystem schema; tracked in Hasura.

BEGIN;

---------------------------------
-- transaction_fees_per_period
---------------------------------
create or replace function ecosystem.transaction_fees_per_period (
    entity_ids entity_id[],
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric
language sql stable
as $$

-- transactions where entity is payer and between timestamp
with payer_transactions as (
	select consensus_timestamp, charged_tx_fee from public.transaction
		where payer_account_id = any(entity_ids)
		and consensus_timestamp between start_timestamp and end_timestamp
),
transactions as (
	select
	date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
	sum(charged_tx_fee) as total
	from payer_transactions
	group by 1
)


select
  'transaction_fees_per_period' as name,
	period,
	int8range(
		period_start_timestamp::timestamp9::bigint,
		(lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
	) as timestamp_range,
	transactions.total
from transactions

$$;

COMMIT;
