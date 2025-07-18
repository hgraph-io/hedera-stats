-- NFT collection sales volume (aggregate)
CREATE 
OR REPLACE FUNCTION ecosystem.nft_collection_sales_volume_aggregate(token_ids bigint[]) RETURNS TABLE (
  token_id bigint, collection_name text, 
  total_tinybar bigint
) AS $$ BEGIN 
SET 
  LOCAL timezone = 'UTC';
RETURN QUERY WITH tokens AS (
  SELECT 
    unnest(token_ids) AS token_id
), 
sales AS (
  SELECT 
    nt.token_id, 
    SUM(ct.amount):: bigint AS total_tinybar 
  FROM 
    public.nft_transfer nt 
    JOIN public.transaction tx ON nt.consensus_timestamp = tx.consensus_timestamp 
    AND tx.type <> 37 
    JOIN public.crypto_transfer ct ON ct.consensus_timestamp = tx.consensus_timestamp 
    AND ct.amount > 0 
  WHERE 
    nt.token_id = ANY(token_ids) 
  GROUP BY 
    nt.token_id
) 
SELECT 
  tokens.token_id, 
  t.name :: text AS collection_name, 
  COALESCE(s.total_tinybar, 0) AS total_tinybar 
FROM 
  tokens 
  JOIN public.token t ON t.token_id = tokens.token_id 
  LEFT JOIN sales s ON s.token_id = tokens.token_id 
ORDER BY 
  total_tinybar DESC;
END $$ LANGUAGE plpgsql;
