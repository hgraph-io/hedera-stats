-- ============================================================================
-- ENG-399: Add contract_type to erc.token_account
-- ============================================================================
-- Issue: https://linear.app/hgraph/issue/ENG-399


BEGIN;

-- Add the contract_type column (nullable initially for backfill)
ALTER TABLE erc.token_account 
ADD COLUMN IF NOT EXISTS contract_type TEXT;

-- Create composite index for efficient filtering queries
-- Enables: WHERE account_id = X AND contract_type = 'ERC_721'
CREATE INDEX IF NOT EXISTS idx_erc_token_account_account_contract_type 
ON erc.token_account(account_id, contract_type);

-- Verify schema changes
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'erc' 
  AND table_name = 'token_account' 
  AND column_name = 'contract_type';

-- Verify indexes
SELECT 
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'token_account' 
  AND schemaname = 'erc'
  AND indexname LIKE '%contract_type%';

COMMIT;


