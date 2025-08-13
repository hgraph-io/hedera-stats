-- EXAMPLE QUERY: NFT collection sales volume

SELECT
  *
FROM
  ecosystem.nft_collection_sales_volume(
    ARRAY[878200, 1350444, 2179656, 6178143,
    6024491], 'day',
    50
);

--drop table ecosystem._nft_collection_sales_volume cascade;

-- CREATE TABLE: NFT collection sales volume

create table ecosystem._nft_collection_sales_volume(
  token_id bigint,
  collection_name text,
  nft_period timestamp,
  total bigint
);

-- CREATE FUNCTION: NFT collection sales volume

CREATE OR REPLACE FUNCTION ecosystem.nft_collection_sales_volume(
  token_ids bigint[],
  period text,
  row_limit integer
)
RETURNS SETOF ecosystem._nft_collection_sales_volume
LANGUAGE sql
STABLE
AS $$
WITH
bounds AS (
  SELECT
    date_trunc(period, CURRENT_TIMESTAMP) AS current_period,
    (period)::text AS p,
    row_limit AS n
),
periods AS (
  SELECT generate_series(
           (SELECT current_period - ((n - 1) || ' ' || p)::interval FROM bounds),
           (SELECT current_period FROM bounds),
           ('1 ' || (SELECT p FROM bounds))::interval
         ) AS nft_period
),
min_ts AS (
  SELECT (EXTRACT(EPOCH FROM (SELECT min(nft_period) FROM periods)) * 1e9)::bigint AS ts
),
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
    AND tx.consensus_timestamp >= (SELECT ts FROM min_ts)
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
-- 4) Treasuries for ANY NFT token moved in the tx
tx_treasuries AS (
  SELECT DISTINCT
    ex.consensus_timestamp,
    tok.treasury_account_id
  FROM expanded ex
  JOIN public.token tok ON tok.token_id = ex.token_id
),
-- 5) Positive HBAR per tx, excluding treasuries
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
-- 6) Allocate per tx, then bucket by period
allocated_by_bucket AS (
  SELECT
    x.token_id,
    date_trunc((SELECT p FROM bounds), to_timestamp(x.consensus_timestamp/1e9)) AS nft_period,
    SUM( (txh.pos_hbar::numeric * x.num_nfts) / NULLIF(st.total_nfts, 0) )::bigint AS total
  FROM tx_token_nft x
  JOIN sale_tx     st  ON st.consensus_timestamp = x.consensus_timestamp
  JOIN tx_pos_hbar txh ON txh.consensus_timestamp = x.consensus_timestamp
  GROUP BY x.token_id, nft_period
)
SELECT
  req.token_id,
  t.name::text AS collection_name,
  p.nft_period,
  COALESCE(ab.total, 0)::bigint AS total
FROM (SELECT DISTINCT unnest($1) AS token_id) req
CROSS JOIN periods p
JOIN public.token t ON t.token_id = req.token_id
LEFT JOIN allocated_by_bucket ab
       ON ab.token_id  = req.token_id
      AND ab.nft_period = p.nft_period
ORDER BY p.nft_period DESC, total DESC;
$$;
