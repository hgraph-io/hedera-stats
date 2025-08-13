-- EXAMPLE QUERY: NFT collection sales volume (total)

SELECT *
FROM ecosystem.nft_collection_sales_volume_total(
  ARRAY[4573896, 6024491, 5959530, 2153883, 9105927, 2179656, 9206452, 1298985, 5959486, 2021726, 
      8302178, 1317352, 1518297, 9218794, 9318575, 9290188, 8308459, 7898692, 9273095, 1350444, 
      1898089, 7864631, 6178143, 8807608, 9352093, 9265340, 7850408, 7324928, 9171591, 8253153, 
      9360058, 9365764, 1940568, 9338706, 9319410, 3958932, 9314891, 6446451, 9351552, 7900254, 
      9362909, 9223982, 9208771, 9215195, 9321287, 7836345, 9364736, 8306822, 7695396, 8174013, 
      9217363, 8345284, 8233302, 8091046, 9365017, 8078650, 4828163, 9361043, 8349904, 7993221, 
      6995252, 8331067, 8507311, 9176498, 8341633, 8337488, 8233316, 8324067, 8101681, 9335709, 
      9345988, 8343395, 8993426, 9169814, 8032018, 9179054, 5194480, 7972726, 9183020, 8312952, 
      8061402, 8070430, 1466871, 8344507, 8040512, 9233876, 7561083, 9177829, 8061839, 7695326, 
      8077096, 9348632, 8422130],
  0::bigint
);

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
