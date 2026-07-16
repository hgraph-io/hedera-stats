-- 003-grants.sql — grant read access on the public last-24h matviews to the
-- readonly role (consumer/API roles inherit from it, so Hasura can serve them).
-- Runs as <db>_owner (owns the matviews). :"readonly_role" is passed by
-- migrate.sh (defaults to <db>_readonly). Idempotent.

BEGIN;

GRANT SELECT ON public.transactions_last_24hrs          TO :"readonly_role";
GRANT SELECT ON public.contract_transactions_last_24hrs TO :"readonly_role";

COMMIT;
