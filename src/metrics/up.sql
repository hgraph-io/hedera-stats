-------------------------------
-- Setup
-------------------------------

-- metrics table
create table if not exists ecosystem.metric (
    -- naming convention: <entity>_<action> (e.g. account_associated_nft)
    name text,
    period text,
    timestamp_range int8range,
    total bigint,
    unique (name, period, timestamp_range)
);
-- if migrating from a previous version
-- alter table ecosystem.metric add unique (name, period, timestamp_range);
-- alter table ecosystem.metric drop constraint metric_name_timestamp_range_key;

-- metric_description table
create table if not exists ecosystem.metric_description (
    name text primary key not null,
    description text,
    methodology text
);

-- return type for metric calculation functions
do $$ begin
	create type ecosystem.metric_total as (
			int8range int8range,
			total bigint
	);
	raise notice 'CREATE TYPE';
exception
    when duplicate_object
			then
				raise notice 'type "ecosystem.metric_total" already exists, skipping';
end $$;

-------------------------------
-- Helpers
-------------------------------
create or replace function ecosystem.metric_start_date(_row ecosystem . metric)
returns timestamp
language sql stable
as $$
	select lower(_row.timestamp_range)::timestamp9::timestamp at time zone 'UTC';
$$;

create or replace function ecosystem.metric_end_date(_row ecosystem . metric)
returns timestamp
language sql stable
as $$
	select upper(_row.timestamp_range)::timestamp9::timestamp at time zone 'UTC';
$$;
