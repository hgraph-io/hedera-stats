-- 074-associated_transaction_fees_per_period.sql — per-period fees across all entity interactions
-- Moved from the legacy ecosystem schema; tracked in Hasura.

BEGIN;

---------------------------------
-- associated_transaction_fees_per_period
---------------------------------
create or replace function ecosystem.associated_transaction_fees_per_period (
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
	select transaction.consensus_timestamp
	from transaction
		where payer_account_id = any(entity_ids)
		and consensus_timestamp between start_timestamp and end_timestamp
),
smart_contract_calls as (
	select contract_result.consensus_timestamp
	from contract_result
	where contract_id = any(entity_ids)
		and contract_result.consensus_timestamp between start_timestamp and end_timestamp
),
token_transfers as (
	select token_transfer.consensus_timestamp
	from token_transfer
	where token_id = any(entity_ids)
		and token_transfer.consensus_timestamp between start_timestamp and end_timestamp
),
nft_transfers as (
	select upper(timestamp_range) as consensus_timestamp
	from nft_history
	where token_id = any(entity_ids)
		and upper(timestamp_range) between start_timestamp and end_timestamp
),
topic_messages as (
	select topic_message.consensus_timestamp
	from topic_message
	where topic_id = any(entity_ids)
		and topic_message.consensus_timestamp between start_timestamp and end_timestamp
),
consensus_timestamps as (
	-- union removes duplicate rows
	select consensus_timestamp from (
		( select consensus_timestamp from payer_transactions )
			union
		( select consensus_timestamp from smart_contract_calls )
			union
		( select consensus_timestamp from token_transfers )
			union
		( select consensus_timestamp from nft_transfers )
			union
		( select consensus_timestamp from topic_messages )
	)
),
transactions as (
	select
		date_trunc(period, cs.consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
		sum(charged_tx_fee) as total
	from consensus_timestamps cs
	join transaction on cs.consensus_timestamp = transaction.consensus_timestamp
	group by 1
)

select
  'associated_transaction_fees_per_period' as name,
	period,
	int8range(
		period_start_timestamp::timestamp9::bigint,
		(lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
	) as timestamp_range,
	transactions.total
from transactions

$$;

COMMIT;
