-- 001-init.sql — first-time bring-up for a stats subscriber.
--
-- The bootstrap migration: the ecosystem schema skeleton (persisted tables,
-- metric_total return type, row-helper functions). Everything is idempotent
-- (CREATE ... IF NOT EXISTS / OR REPLACE, duplicate_object guards), so
-- re-applying is a no-op. The metric functions, descriptions, seed and load
-- procedures follow in 002+.
--
-- Migration convention: migrations/NNN-name.sql, applied in filename order.
-- Add the next change as a new NNN-*.sql rather than editing this file.
--
-- These migrations create objects ONLY in the ecosystem schema — never in
-- public. Everything in public (the replicated mirror-node tables and their
-- enum/domain types) and the timestamp9 / http extensions are external
-- prerequisites, provisioned by a superuser / the mirror node itself. The
-- ecosystem_owner role has no rights on public.
--   https://github.com/optiver/timestamp9
--   https://github.com/pramsey/pgsql-http

create schema if not exists ecosystem;

-- Central table storing all calculated metrics.
create table if not exists ecosystem.metric (
    -- naming convention: <entity>_<action> (e.g. account_associated_nft)
    name text,
    period text,
    timestamp_range int8range,
    total bigint,
    unique (name, period, timestamp_range)
);

-- Metadata describing each metric (seeded by src/metric_descriptions.sql).
create table if not exists ecosystem.metric_description (
    name text primary key not null,
    description text,
    methodology text
);

-- Return type for metric calculation functions.
do $$ begin
    create type ecosystem.metric_total as (
        int8range int8range,
        total bigint
    );
    raise notice 'CREATE TYPE';
exception
    when duplicate_object then
        raise notice 'type "ecosystem.metric_total" already exists, skipping';
end $$;

-- Row helpers: expose the int8range bounds as readable UTC timestamps.
create or replace function ecosystem.metric_start_date(_row ecosystem.metric)
returns timestamp
language sql stable
as $$
    select lower(_row.timestamp_range)::timestamp9::timestamp at time zone 'UTC';
$$;

create or replace function ecosystem.metric_end_date(_row ecosystem.metric)
returns timestamp
language sql stable
as $$
    select upper(_row.timestamp_range)::timestamp9::timestamp at time zone 'UTC';
$$;
