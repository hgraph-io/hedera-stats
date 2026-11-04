-- 105-hbar_total_released_from_balances.sql — hbar_total_released from the mirror
-- node's balance snapshots instead of re-summing every treasury transfer since genesis.
--
-- released(T) = total supply (50B HBAR) − Σ treasury balances at T, where each
-- treasury balance at T is its latest account_balance snapshot before T plus the
-- transfers between that snapshot and T (the 15-minute-or-less top-up keeps period
-- boundaries exact). The treasury set is the mirror node's unreleased-supply list,
-- unchanged from 013.
--
-- Why: 013 summed `crypto_transfer where consensus_timestamp between 0 and end`
-- on every call — a full-history scan (~8 min per call on testnet, repeated every
-- hourly run) that is also wrong wherever crypto_transfer does not reach back to
-- genesis (testnet's starts 2024-02-01, so every testnet value omitted all earlier
-- flows). This version costs a few index lookups per treasury account per period.
--
-- Verified on mainnet before writing: identical to every stored day in Oct 2026
-- (31/31) and every hour of 2026-11-02 (24/24, same ranges), and equal to the mirror
-- node REST /api/v1/network/supply released_supply on both networks; Σ(stored +
-- treasury balances) is exactly 5e18 at boundaries in 2024, 2025 and 2026.
--
-- This is the mirror node's own formula (rest-java NetworkServiceImpl.getSupply):
-- current supply = 50B − Σ entity.balance over the unreleased-supply accounts
-- (NetworkProperties.unreleasedSupplyAccounts, the same ranges as below); historical
-- supply = 50B − Σ each account's latest account_balance row. It adds no transfers
-- after the snapshot, so its historical answer is as of the snapshot; the top-up here
-- makes ours exact at the period boundary.
--
-- Behaviour notes:
--   * Emits every COMPLETE period in the window with a closed range
--     [period_start, period_start + 1 period), so the newest complete period is
--     stored on the next load (013's lead() upper bound held it back one period).
--   * Only covers periods ending after the first balance snapshot (mainnet:
--     2023-10-24); earlier history is already stored and is never recomputed.
--   * `entity_id <> 98` lets the planner use crypto_transfer's partial
--     (entity_id, consensus_timestamp) index; 0.0.98 is not a treasury account.

BEGIN;

CREATE OR REPLACE FUNCTION ecosystem.hbar_total_released(
    period text,
    start_timestamp bigint DEFAULT 0,
    end_timestamp bigint DEFAULT current_timestamp::timestamp9::bigint
)
RETURNS SETOF ecosystem.metric_total
LANGUAGE sql STABLE
AS $$
with treasury(account_id) as (
    select unnest(array[2, 42])                -- 0.0.2 primary treasury, 0.0.42
    union all select generate_series(44, 71)
    union all select generate_series(73, 87)
    union all select generate_series(99, 100)
    union all select generate_series(200, 349)
    union all select generate_series(400, 750)
),
step as (
    select case period when 'quarter' then interval '3 months'
                       else ('1 ' || period)::interval end as i
),
bounds as (
    -- Clamp to the first snapshot so a call with the default start (0) does not
    -- generate periods back to 1970.
    select greatest(
               start_timestamp,
               (select min(consensus_timestamp) from account_balance where account_id = 2)
           ) as start_ts
),
periods as (
    select ps, ps + step.i as pe
    from step, bounds,
         generate_series(date_trunc(period, bounds.start_ts::timestamp9::timestamp),
                         date_trunc(period, end_timestamp::timestamp9::timestamp) - step.i,
                         step.i) as ps
),
released as (
    select
        p.ps,
        p.pe,
        5000000000000000000 - sum(coalesce(s.balance, 0) + coalesce(t.flow, 0)) as total,
        count(s.balance) as covered
    from periods p
    cross join treasury a
    left join lateral (
        select ab.balance, ab.consensus_timestamp
        from account_balance ab
        where ab.account_id = a.account_id
          and ab.consensus_timestamp < p.pe::timestamp9::bigint
          -- account_balance is partitioned by month and the importer writes a FULL
          -- snapshot as the first one of each partition (deduplicated after that), so
          -- every account's latest row is never older than the start of the previous
          -- month. Same lower bound as the mirror node REST supply query
          -- (NetworkServiceImpl.getFirstDayOfMonth(max, -1)); lets each lookup prune to
          -- two partitions instead of all of them.
          and ab.consensus_timestamp >= (date_trunc('month', p.pe - interval '1 microsecond')
                                         - interval '1 month')::timestamp9::bigint
        order by ab.consensus_timestamp desc
        limit 1
    ) s on true
    left join lateral (
        select sum(ct.amount) as flow
        from crypto_transfer ct
        where ct.entity_id = a.account_id
          and ct.entity_id <> 98
          and ct.consensus_timestamp > s.consensus_timestamp
          and ct.consensus_timestamp < p.pe::timestamp9::bigint
    ) t on true
    group by p.ps, p.pe
)
select
    int8range(ps::timestamp9::bigint, pe::timestamp9::bigint),
    total
from released
where covered = (select count(*) from treasury)   -- every treasury account has a snapshot before pe
order by ps;
$$;

COMMIT;
