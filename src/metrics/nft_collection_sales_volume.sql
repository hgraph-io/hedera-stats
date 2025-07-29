-- Example query

SELECT
  *
FROM
  ecosystem.nft_collection_sales_volume(
    ARRAY[878200, 1350444, 2179656, 6178143,
    6024491], 'day',
    50
);

--drop table ecosystem._nft_collection_sales_volume cascade;

create table ecosystem._nft_collection_sales_volume(
  token_id bigint,
  collection_name text,
  nft_period timestamp,
  total bigint
);
-- NFT collection sales volume
CREATE OR REPLACE FUNCTION ecosystem.nft_collection_sales_volume(
  token_ids bigint[],
  period text,
  row_limit integer
)
RETURNS SETOF ecosystem._nft_collection_sales_volume
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  current_period timestamp;
  start_period timestamp;
  min_consensus_ts bigint;
BEGIN
  current_period := date_trunc(period, CURRENT_TIMESTAMP);
  start_period := current_period - ((row_limit - 1) || ' ' || period)::INTERVAL;
  min_consensus_ts := (EXTRACT(EPOCH FROM start_period) * 1e9)::BIGINT;

  RETURN QUERY
  WITH tokens AS (
    SELECT unnest(token_ids) AS token_id
  ),
  periods AS (
    SELECT generate_series(start_period, current_period, ('1 ' || period)::INTERVAL) AS nft_period
  ),
  combos AS (
    SELECT tokens.token_id, periods.nft_period 
    FROM tokens 
    CROSS JOIN periods
  ),
  sales AS (
    SELECT 
      nt.token_id,
      date_trunc(period, to_timestamp(nt.consensus_timestamp / 1e9)) AS nft_period,
      SUM(ct.amount)::bigint AS total
    FROM 
      public.nft_transfer nt
      JOIN public.transaction tx ON nt.consensus_timestamp = tx.consensus_timestamp AND tx.type <> 37
      JOIN public.crypto_transfer ct ON ct.consensus_timestamp = tx.consensus_timestamp AND ct.amount > 0
    WHERE 
      nt.token_id = ANY(token_ids)
      AND nt.consensus_timestamp >= min_consensus_ts
    GROUP BY 
      nt.token_id, nft_period
  )
  SELECT 
    c.token_id,
    t.name::text AS collection_name,
    c.nft_period,
    COALESCE(s.total, 0)::bigint AS total
  FROM 
    combos c
    JOIN public.token t ON t.token_id = c.token_id
    LEFT JOIN sales s ON s.token_id = c.token_id AND s.nft_period = c.nft_period
  ORDER BY 
    c.nft_period DESC,
    total DESC;

END;
$$;

