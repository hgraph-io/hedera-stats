-- 002-contract_transactions_last_24hrs.sql — public matview: contract-transaction
-- count over the last 24h (transaction types 7, 8, 9, 22). PUBLIC migration set
-- (applied as <db>_owner). The legacy source put this function in ecosystem and
-- the matview in public; here both live in public so the set is self-contained.
--
-- Materialized view: not replicated, needs a scheduled REFRESH on each node.

BEGIN;

create or replace function public.contract_transactions_last_24hrs()
returns bigint
language plpgsql stable
as $$
declare
  _now timestamp9 := now()::timestamp9;
  start_timestamp bigint := (_now - interval '1 day' - interval '1 minute')::timestamp9::bigint;
  end_timestamp bigint := (_now - interval '1 minute')::timestamp9::bigint;
  latest_timestamp bigint := (select consensus_timestamp from transaction order by consensus_timestamp desc limit 1);
  total bigint;
begin
  if latest_timestamp < end_timestamp then
    raise exception 'Data import is behind, not recomputing contract_transactions_last_24hrs';
  end if;
  select count(*) into total
  from transaction
  where consensus_timestamp between start_timestamp and end_timestamp
    and type in ( 7, 8, 9, 22 );
  return total;
end
$$;

create materialized view if not exists public.contract_transactions_last_24hrs as
select
  public.contract_transactions_last_24hrs() as count,
  now() at time zone 'utc' - interval '1 minute' as updated_at;

create unique index if not exists contract_transactions_last_24hrs_count_updated_at_idx
  on public.contract_transactions_last_24hrs (count, updated_at);

COMMIT;
