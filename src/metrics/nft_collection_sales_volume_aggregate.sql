-- NFT collection sales volume (aggregate)
CREATE OR REPLACE FUNCTION ecosystem.nft_collection_sales_volume_aggregate(
  token_ids bigint[],
  start_ts bigint DEFAULT 0, 
  end_ts bigint DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000000000)::bigint
) RETURNS TABLE (
  token_id bigint, collection_name text, 
  total_tinybar bigint
) AS $$ 
BEGIN 
SET LOCAL timezone = 'UTC';

CREATE TEMP TABLE temp_tokens (token_id bigint PRIMARY KEY) ON COMMIT DROP;
INSERT INTO temp_tokens (token_id)
SELECT DISTINCT unnest(token_ids);

ANALYZE temp_tokens;

RETURN QUERY WITH 
expanded_nfts AS (
  SELECT 
    tx.consensus_timestamp,
    ((e.elem ->> 'token_id')::bigint) AS token_id,
    1 AS num_nfts
  FROM public.transaction tx
  CROSS JOIN jsonb_array_elements(tx.nft_transfer) AS e(elem)
  JOIN temp_tokens tt ON ((e.elem ->> 'token_id')::bigint) = tt.token_id
  WHERE tx.nft_transfer IS NOT NULL
    AND tx.consensus_timestamp > start_ts
    AND tx.consensus_timestamp < end_ts
    AND tx.type <> 37
),
nt_details AS (
  SELECT 
    en.consensus_timestamp,
    en.token_id,
    SUM(en.num_nfts) AS num_nfts 
  FROM expanded_nfts en
  GROUP BY en.consensus_timestamp, en.token_id
),
tx_details AS (
  SELECT 
    ntd.consensus_timestamp,
    SUM(ntd.num_nfts) AS total_nfts
  FROM nt_details ntd
  GROUP BY ntd.consensus_timestamp
),
ct_total AS (
  SELECT 
    ed.consensus_timestamp,
    SUM(ct.amount)::bigint AS total_tinybar
  FROM (SELECT DISTINCT en.consensus_timestamp FROM expanded_nfts en) ed
  JOIN public.crypto_transfer ct ON ct.consensus_timestamp = ed.consensus_timestamp AND ct.amount > 0
  GROUP BY ed.consensus_timestamp
),
sales AS (
  SELECT 
    nt.token_id, 
    SUM(
      CASE 
        WHEN td.total_nfts > 0 THEN ((COALESCE(ct.total_tinybar, 0)::numeric * nt.num_nfts) / td.total_nfts)
        ELSE 0
      END
    )::bigint AS total_tinybar
  FROM nt_details nt
  JOIN tx_details td ON nt.consensus_timestamp = td.consensus_timestamp
  LEFT JOIN ct_total ct ON ct.consensus_timestamp = td.consensus_timestamp
  GROUP BY nt.token_id
)
SELECT 
  tt.token_id, 
  t.name::text AS collection_name, 
  COALESCE(s.total_tinybar, 0) AS total_tinybar 
FROM 
  temp_tokens tt
  JOIN public.token t ON t.token_id = tt.token_id 
  LEFT JOIN sales s ON s.token_id = tt.token_id 
ORDER BY 
  total_tinybar DESC;
END
$$ LANGUAGE plpgsql;