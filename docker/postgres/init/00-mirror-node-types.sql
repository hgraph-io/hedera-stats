-- =====================================================
-- Mirror Node Types
-- =====================================================
-- Mirror node tables use custom enum and domain types. To import them
-- as foreign tables via postgres_fdw, the same type names must exist
-- locally in the stats database. These definitions are kept minimal -
-- just enough for foreign table definitions to succeed.
-- =====================================================

-- Enum types
DO $$ BEGIN
  CREATE TYPE entity_type AS ENUM ('UNKNOWN', 'ACCOUNT', 'CONTRACT', 'FILE', 'TOPIC', 'TOKEN', 'SCHEDULE');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE token_type AS ENUM ('FUNGIBLE_COMMON', 'NON_FUNGIBLE_UNIQUE');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE transfer_type AS ENUM ('hbar', 'fungible_token', 'non_fungible_token', 'staking_reward');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE errata_type AS ENUM ('INSERT', 'DELETE');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE token_pause_status AS ENUM ('NOT_APPLICABLE', 'PAUSED', 'UNPAUSED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE token_supply_type AS ENUM ('INFINITE', 'FINITE');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Domain types
DO $$ BEGIN CREATE DOMAIN nanos_timestamp  AS bigint;       EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE DOMAIN entity_id        AS bigint;       EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE DOMAIN entity_num       AS integer;      EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE DOMAIN entity_realm_num AS smallint;     EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE DOMAIN entity_type_id   AS char(1);      EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE DOMAIN hbar_tinybars    AS bigint;       EXCEPTION WHEN duplicate_object THEN NULL; END $$;
