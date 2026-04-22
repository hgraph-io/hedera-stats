create schema if not exists ecosystem;

-- Extensions are created by docker/postgres/init/01-init.sh. pg_cron lives
-- in the default "postgres" database; timestamp9 and http live here.
-- https://github.com/citusdata/pg_cron
-- https://github.com/optiver/timestamp9
-- https://github.com/pramsey/pgsql-http

create table if not exists ecosystem.metric (
    -- naming convention: <entity>_<action> (e.g. account_associated_nft)
    name text,
    period text,
    timestamp_range int8range,
    total bigint,
    unique (name, period, timestamp_range)
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
