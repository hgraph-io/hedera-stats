-- 084-grants.sql — grant read access on the ecosystem schema to the readonly role.
--
-- Consumer/API roles (e.g. <db>_api) inherit from <db>_readonly. Our objects are
-- owned by the ecosystem_owner role and, without these grants, readonly (and
-- thus api) can't see the schema — which is why Hasura, introspecting as api,
-- reports ecosystem functions/tables as untrackable ("does not return a table",
-- "no such table"). The publisher already has these grants (from its old deploy);
-- this reproduces them on subscribers where our migrations created the schema.
--
-- Runs as the ecosystem_owner (the deploy sets PGOPTIONS role=...), which owns
-- these objects and can grant. :"readonly_role" is passed by migrate.sh
-- (defaults to <db>_readonly). Idempotent — safe to re-run.
--
-- ALTER DEFAULT PRIVILEGES omits FOR ROLE, so it binds to the current role
-- (the owner): objects created by LATER migrations are auto-granted too.

BEGIN;

GRANT USAGE   ON SCHEMA ecosystem                  TO :"readonly_role";
GRANT SELECT  ON ALL TABLES    IN SCHEMA ecosystem TO :"readonly_role";
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ecosystem TO :"readonly_role";

ALTER DEFAULT PRIVILEGES IN SCHEMA ecosystem GRANT SELECT  ON TABLES    TO :"readonly_role";
ALTER DEFAULT PRIVILEGES IN SCHEMA ecosystem GRANT EXECUTE ON FUNCTIONS TO :"readonly_role";

COMMIT;
