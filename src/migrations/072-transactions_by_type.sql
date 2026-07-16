-- 072-transactions_by_type.sql — transaction counts grouped by type for payer accounts
-- Moved from the legacy ecosystem schema; tracked in Hasura.

BEGIN;

create or replace function ecosystem.transactions_by_type (
    entity_ids entity_id[],
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . transaction_count_by_type
language sql stable
as $$

select type, count(*)
from transaction
		where payer_account_id = any(entity_ids)
		and consensus_timestamp between start_timestamp and end_timestamp
group by 1

$$;

COMMIT;
