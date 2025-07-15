create or replace function ecosystem.contract_transactions_last_24hrs()
returns bigint
language plpgsql stable
as $$

declare
  _now timestamp9 := now():: timestamp9;
  start_timestamp bigint := (_now - interval '1 day' - interval '1 minute')::timestamp9::bigint;
  end_timestamp bigint := (_now - interval '1 minute')::timestamp9::bigint;
  latest_timestamp bigint := (select consensus_timestamp from transaction order by consensus_timestamp desc limit 1);
  total bigint;

begin
  if latest_timestamp < end_timestamp then
    raise exception 'Data import is behind, not recomputing contract_transactions_last_24hrs';
  end if;

  select count(*)
  into total
  from transaction
  where consensus_timestamp between start_timestamp and end_timestamp
  and type in ( 7, 8, 9, 22 );

  return total;
end

$$;

-- contract_transactions_last_24hrs
drop materialized view if exists contract_transactions_last_24hrs;

create materialized view contract_transactions_last_24hrs as
select
  ecosystem.contract_transactions_last_24hrs() as count,
  now() at time zone 'utc' - interval '1 minute' as updated_at;

create unique index on contract_transactions_last_24hrs (count, updated_at);
