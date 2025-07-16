-- Main function to calculate transactions in the last 24 hours
create or replace function transactions_last_24hrs()
returns bigint
language plpgsql stable
as $$

declare
  same_now timestamp9 := now():: timestamp9;
  start_timestamp bigint := cast(same_now - interval '1 day' - interval '1 minute' as bigint);
  end_timestamp bigint := cast(same_now - interval '1 minute' as bigint);
  latest_timestamp bigint := (select consensus_timestamp from transaction order by consensus_timestamp desc limit 1);
  total bigint;

begin

  if latest_timestamp < end_timestamp then
    raise exception 'Data import is behind, not recomputing transactions_last_24hrs';
  end if;

  select count(*)
  into total
  from transaction
  where consensus_timestamp > start_timestamp
  and consensus_timestamp < end_timestamp;

  return total;
end
$$;


drop materialized view if exists transactions_last_24hrs;

create materialized view transactions_last_24hrs as
select
	transactions_last_24hrs() as count,
	now() at time zone 'utc' - interval '1 minute' as updated_at;

create unique index on transactions_last_24hrs (count, updated_at);

-- total_acccounts
drop materialized view if exists total_accounts;
create materialized view total_accounts as
select
	count(*),
	now() at time zone 'utc' - interval '1 minute' as updated_at
from entity
where type = 'ACCOUNT';
create unique index on total_accounts (count, updated_at);
