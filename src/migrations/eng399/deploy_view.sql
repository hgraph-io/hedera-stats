-- ENG-399: Add contract_type filtering to erc.token_account
-- Creates view exposing contract_type field by joining with erc.token

BEGIN;

CREATE OR REPLACE VIEW erc.token_account_with_type AS
SELECT 
    ta.account_id,
    ta.token_id,
    ta.balance,
    ta.balance_timestamp,
    ta.created_timestamp,
    ta.associated,
    ta.token_evm_address,
    t.contract_type
FROM erc.token_account ta
INNER JOIN erc.token t ON t.token_id = ta.token_id;

COMMIT;

-- Validation
SELECT 
    COUNT(*) AS view_rows,
    (SELECT COUNT(*) FROM erc.token_account) AS table_rows,
    CASE 
        WHEN COUNT(*) = (SELECT COUNT(*) FROM erc.token_account) 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status
FROM erc.token_account_with_type;

SELECT 
    contract_type,
    COUNT(*) AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM erc.token_account_with_type
GROUP BY contract_type
ORDER BY COUNT(*) DESC;
