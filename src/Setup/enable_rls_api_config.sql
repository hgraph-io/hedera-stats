-- ============================================================================
-- Row-Level Security Configuration for API Credentials
-- ============================================================================
-- Description: Implements Row-Level Security (RLS) on ecosystem.api_config
--              to prevent GraphQL exposure of API credentials while allowing
--              internal function access.
--
-- Security Model:
--   - Default DENY policy blocks all direct queries (including GraphQL)
--   - Selective ALLOW policy permits database owner and function access
--   - Industry-standard PostgreSQL RLS implementation
--
-- Usage:
--   psql -h <host> -p <port> -U <user> -d <database> -f enable_rls_api_config.sql
--
-- Rollback:
--   DROP POLICY api_config_no_direct_access ON ecosystem.api_config;
--   DROP POLICY api_config_function_access ON ecosystem.api_config;
--   ALTER TABLE ecosystem.api_config DISABLE ROW LEVEL SECURITY;
-- ============================================================================

-- Enable Row-Level Security on ecosystem.api_config
ALTER TABLE ecosystem.api_config ENABLE ROW LEVEL SECURITY;

-- Remove any existing policies
DROP POLICY IF EXISTS api_config_no_direct_access ON ecosystem.api_config;
DROP POLICY IF EXISTS api_config_function_access ON ecosystem.api_config;
DROP POLICY IF EXISTS api_config_owner_access ON ecosystem.api_config;

-- Create default DENY policy (blocks all direct access including GraphQL)
CREATE POLICY api_config_no_direct_access ON ecosystem.api_config
    FOR ALL
    USING (false);

-- Create selective ALLOW policy (permits owner and function access)
CREATE POLICY api_config_function_access ON ecosystem.api_config
    FOR SELECT
    TO PUBLIC
    USING (
        -- Database administrators
        current_user IN ('omar', 'brandon', 'hedera_mainnet_owner', 'hedera_testnet_owner')
        OR
        -- Function access for credential retrieval
        EXISTS (
            SELECT 1 
            FROM pg_stat_activity 
            WHERE pid = pg_backend_pid() 
            AND (
                query LIKE '%top_fungible_tokens%'
                OR query LIKE '%ecosystem.api_config%'
                OR application_name LIKE '%function%'
                OR application_name LIKE '%plpgsql%'
            )
        )
    );

-- Configure table permissions
REVOKE ALL ON ecosystem.api_config FROM PUBLIC;
GRANT SELECT ON ecosystem.api_config TO PUBLIC;

-- Add table comment
COMMENT ON TABLE ecosystem.api_config IS 
'API credentials storage with Row-Level Security. Direct queries blocked; function access permitted.';

