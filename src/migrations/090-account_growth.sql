-- 090-account_growth.sql — account_growth metric: retail accounts created per period (non-contract
-- accounts that have never paid a developer-type transaction).
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

CREATE OR REPLACE FUNCTION ecosystem.account_growth(period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$
with retail_created_accounts as (
    select
        id,
        created_timestamp
    from entity
    where type != 'CONTRACT' -- not smart contracts
    and created_timestamp between start_timestamp and end_timestamp
    and not exists (
        select 1
        from transaction t
        where
            entity.id = t.payer_account_id
            and type in (8, 9, 29, 36, 37, 58, 24, 25) -- no developer transactions
    )
),
retail_created_accounts_per_period as (
    select
        date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
        count(distinct id) as total
    from retail_created_accounts
    group by 1
    order by 1 desc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
    ),
    total
from retail_created_accounts_per_period

$$;

COMMIT;
