-- 001-init.sql — first-time bring-up for a stats subscriber.
--
-- The bootstrap migration: extensions, the mirror-node enum/domain types, and
-- the ecosystem schema skeleton (persisted tables, metric_total return type,
-- row-helper functions). Everything is idempotent (CREATE ... IF NOT EXISTS /
-- OR REPLACE, duplicate_object guards), so re-applying is a no-op. The metric
-- functions, descriptions, seed and load procedures follow in 002+.
--
-- Migration convention: migrations/NNN-name.sql, applied in filename order.
-- Add the next change as a new NNN-*.sql rather than editing this file.
--
-- Prerequisites (provisioned OUTSIDE this migration set, by a superuser): the
-- timestamp9 and http extensions must already exist in the target database.
-- These migrations are pure schema SQL and do not create extensions.
--   https://github.com/optiver/timestamp9
--   https://github.com/pramsey/pgsql-http

-- Mirror-node enum/domain types. The local tables the logical replication
-- subscription replicates into reference these type names, so they must exist
-- locally. Kept minimal — just enough for the replicated table schemas.
do $$ begin create type entity_type as enum ('UNKNOWN','ACCOUNT','CONTRACT','FILE','TOPIC','TOKEN','SCHEDULE'); exception when duplicate_object then null; end $$;
do $$ begin create type token_type as enum ('FUNGIBLE_COMMON','NON_FUNGIBLE_UNIQUE'); exception when duplicate_object then null; end $$;
do $$ begin create type transfer_type as enum ('hbar','fungible_token','non_fungible_token','staking_reward'); exception when duplicate_object then null; end $$;
do $$ begin create type errata_type as enum ('INSERT','DELETE'); exception when duplicate_object then null; end $$;
do $$ begin create type token_pause_status as enum ('NOT_APPLICABLE','PAUSED','UNPAUSED'); exception when duplicate_object then null; end $$;
do $$ begin create type token_supply_type as enum ('INFINITE','FINITE'); exception when duplicate_object then null; end $$;
do $$ begin create domain nanos_timestamp  as bigint;   exception when duplicate_object then null; end $$;
do $$ begin create domain entity_id        as bigint;   exception when duplicate_object then null; end $$;
do $$ begin create domain entity_num       as integer;  exception when duplicate_object then null; end $$;
do $$ begin create domain entity_realm_num as smallint; exception when duplicate_object then null; end $$;
do $$ begin create domain entity_type_id   as char(1);  exception when duplicate_object then null; end $$;
do $$ begin create domain hbar_tinybars    as bigint;   exception when duplicate_object then null; end $$;

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
