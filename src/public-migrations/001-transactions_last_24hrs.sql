-- 001-transactions_last_24hrs.sql — public matview: transaction count over the
-- last 24h. Part of the PUBLIC migration set (applied as the <db>_owner role,
-- which owns the public schema — ecosystem_owner cannot write public).
--
-- Materialized view: not replicated to subscribers, and needs a scheduled
-- REFRESH on each node (cron, a publisher/subscriber concern). Uses IF NOT
-- EXISTS so it is a no-op where the matview already exists.

BEGIN;

create or replace function public.transactions_last_24hrs()
returns bigint
language plpgsql stable
as $$
declare
  same_now timestamp9 := now()::timestamp9;
  start_timestamp bigint := cast(same_now - interval '1 day' - interval '1 minute' as bigint);
  end_timestamp bigint := cast(same_now - interval '1 minute' as bigint);
  latest_timestamp bigint := (select consensus_timestamp from transaction order by consensus_timestamp desc limit 1);
  total bigint;
begin
  if latest_timestamp < end_timestamp then
    raise exception 'Data import is behind, not recomputing transactions_last_24hrs';
  end if;
  select count(*) into total
  from transaction
  where consensus_timestamp > start_timestamp
    and consensus_timestamp < end_timestamp;
  return total;
end
$$;

create materialized view if not exists public.transactions_last_24hrs as
select
  public.transactions_last_24hrs() as count,
  now() at time zone 'utc' - interval '1 minute' as updated_at;

create unique index if not exists transactions_last_24hrs_count_updated_at_idx
  on public.transactions_last_24hrs (count, updated_at);

COMMIT;
