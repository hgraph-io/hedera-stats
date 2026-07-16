-- 069-transaction_count_by_type.sql — count-by-type result table (replicated to subscribers)
-- Moved from the legacy ecosystem schema; tracked in Hasura.

BEGIN;

create table if not exists ecosystem.transaction_count_by_type (
    type smallint,
    total bigint
);

COMMIT;
