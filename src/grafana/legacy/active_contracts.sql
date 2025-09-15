-----------------------
-- Total active smart contracts
-----------------------
create or replace function ecosystem.dashboard_active_contracts(
    _interval interval
)
returns table (
    total bigint,
    previous_total bigint
) as $$

declare
  total bigint;
  previous_total bigint;

  previous_period_start bigint = (now() - _interval * 2)::timestamp9::bigint;
  current_period_start bigint = (now() - _interval )::timestamp9::bigint;

begin
  select count(*) into previous_total from (
    select distinct cr.contract_id
    from contract_result cr
    where cr.consensus_timestamp between previous_period_start and current_period_start
    and cr.transaction_result = 22
  );

  select count(*) into total from (
    select distinct cr.contract_id
    from contract_result cr
    where cr.consensus_timestamp >= current_period_start
    and cr.transaction_result = 22
  );

  return query select total, previous_total;
end

$$ language plpgsql;
