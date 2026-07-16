-- CREATE TABLE: NFT collection sales volume (total)

CREATE TABLE ecosystem._nft_collection_sales_volume_total (
  token_id bigint,
  collection_name text,
  total bigint
);


-- CREATE FUNCTION: NFT collection sales volume (total)

CREATE OR REPLACE FUNCTION ecosystem.nft_collection_sales_volume_total(
  token_ids bigint[],
  start_ts bigint DEFAULT 0,
  end_ts   bigint DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000000000)::bigint
)
RETURNS SETOF ecosystem._nft_collection_sales_volume_total
LANGUAGE sql
STABLE
AS $$
WITH
-- 1) Candidate sale txns with reusable fields (JSON and precomputed total_nfts)
sale_tx AS (
  SELECT
    tx.consensus_timestamp,
    tx.nft_transfer,
    jsonb_array_length(tx.nft_transfer) AS total_nfts
  FROM public.transaction tx
  WHERE tx.nft_transfer IS NOT NULL
    AND tx.result = 22           -- SUCCESS
    AND tx.type <> 37            -- exclude tokenMint
    AND tx.consensus_timestamp > $2  -- start_ts parameter
    AND tx.consensus_timestamp < $3  -- end_ts parameter
    AND EXISTS (
      SELECT 1
      FROM public.crypto_transfer ct
      WHERE ct.consensus_timestamp = tx.consensus_timestamp
        AND ct.amount > 0
    )
),
-- 2) Expand NFT JSON once; tag each element with its token_id
expanded AS (
  SELECT
    st.consensus_timestamp,
    ((e.elem ->> 'token_id')::bigint) AS token_id
  FROM sale_tx st
  CROSS JOIN LATERAL jsonb_array_elements(st.nft_transfer) AS e(elem)
),
-- 3) Only the requested token_ids, with per-tx counts
tx_token_nft AS (
  SELECT
    ex.consensus_timestamp,
    ex.token_id,
    COUNT(*)::bigint AS num_nfts
  FROM expanded ex
  WHERE ex.token_id = ANY ($1)
  GROUP BY ex.consensus_timestamp, ex.token_id
),
-- 4) All treasuries for ANY NFT token moved in the tx (to exclude self/treasury inflows)
tx_treasuries AS (
  SELECT DISTINCT
    ex.consensus_timestamp,
    tok.treasury_account_id
  FROM expanded ex
  JOIN public.token tok ON tok.token_id = ex.token_id
),
-- 5) Positive HBAR per tx, excluding transfers to any treasury from this tx
tx_pos_hbar AS (
  SELECT ct.consensus_timestamp, SUM(ct.amount)::bigint AS pos_hbar
  FROM public.crypto_transfer ct
  WHERE ct.amount > 0
    AND EXISTS (SELECT 1 FROM sale_tx st WHERE st.consensus_timestamp = ct.consensus_timestamp)
    AND NOT EXISTS (
      SELECT 1
      FROM tx_treasuries tr
      WHERE tr.consensus_timestamp = ct.consensus_timestamp
        AND tr.treasury_account_id = ct.entity_id
    )
  GROUP BY ct.consensus_timestamp
),
-- 6) Final per-token allocation: (pos_hbar * token_nfts) / total_nfts
allocated AS (
  SELECT
    x.token_id,
    SUM( (txh.pos_hbar::numeric * x.num_nfts) / NULLIF(st.total_nfts, 0) )::bigint AS total_tinybar
  FROM tx_token_nft x
  JOIN sale_tx     st  ON st.consensus_timestamp = x.consensus_timestamp
  JOIN tx_pos_hbar txh ON txh.consensus_timestamp = x.consensus_timestamp
  GROUP BY x.token_id
)
SELECT
  req.token_id,
  t.name::text AS collection_name,
  COALESCE(a.total_tinybar, 0)::bigint AS total
FROM (SELECT DISTINCT unnest($1) AS token_id) req
JOIN public.token t ON t.token_id = req.token_id
LEFT JOIN allocated a ON a.token_id = req.token_id
ORDER BY COALESCE(a.total_tinybar, 0) DESC;
$$;
