-- ============================================================================
-- SaucerSwap API Configuration - MAINNET ONLY
-- ============================================================================
-- This file sets up API credentials for SaucerSwap integration on MAINNET.
-- ============================================================================

-- Create configuration table
CREATE TABLE IF NOT EXISTS ecosystem.api_config (
    service_name TEXT NOT NULL,
    environment TEXT NOT NULL,
    api_url TEXT NOT NULL,
    api_key TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (service_name, environment) 
);

-- Insert SaucerSwap MAINNET API credentials ONLY
-- NOTE: Replace 'YOUR_MAINNET_API_KEY_HERE' with actual mainnet API key
INSERT INTO ecosystem.api_config (service_name, environment, api_url, api_key)
VALUES 
    ('saucerswap', 'mainnet', 'https://api.saucerswap.finance/tokens', 'YOUR_MAINNET_API_KEY_HERE')
ON CONFLICT (service_name, environment) DO UPDATE 
    SET api_url = EXCLUDED.api_url,
        api_key = EXCLUDED.api_key,
        updated_at = NOW();

-- Add helpful comment
COMMENT ON TABLE ecosystem.api_config IS 
'Stores API credentials for external services. Keeps sensitive data out of code.';

CREATE OR REPLACE VIEW ecosystem.api_config_view AS
SELECT 
    service_name,
    environment,
    api_url,
    LEFT(api_key, 4) || '...' || RIGHT(api_key, 4) AS api_key_masked,
    created_at,
    updated_at
FROM ecosystem.api_config;

COMMENT ON VIEW ecosystem.api_config_view IS 
'Displays API configuration with masked keys for security.';
