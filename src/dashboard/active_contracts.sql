-----------------------
-- Total active smart contracts
-----------------------
create or replace function ecosystem.dashboard_active_contracts(
    _interval interval
)
returns bigint as $$
  select count(*) from (
    select distinct cr.contract_id
    from contract_result cr
    where cr.consensus_timestamp >= (now() - _interval::interval)::timestamp9::bigint
    and cr.transaction_result = 22
  );
$$ language sql;
