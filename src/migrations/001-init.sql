-- 001-init.sql — first-time schema bring-up for a stats subscriber.
--
-- Single source of truth for the ecosystem schema skeleton: the schema, the two
-- persisted tables, the metric_total return type, and the row-helper functions.
-- Everything here is idempotent (CREATE ... IF NOT EXISTS / OR REPLACE, and a
-- duplicate_object guard on the composite type), so re-applying on an existing
-- subscriber is a no-op. Metric functions, descriptions, jobs and pg_cron are
-- loaded separately by docker/postgres/init/01-init.sh after this runs.
--
-- Migration convention follows hg-core: migrations/NNN-name.sql, applied in
-- filename order. Add the next change as 002-*.sql rather than editing this file.
--
-- Extensions (timestamp9, postgres_fdw, http, pg_cron) are created by
-- 01-init.sh, not here — pg_cron lives in the "postgres" database while these
-- objects live in the stats database.
--   https://github.com/citusdata/pg_cron
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
