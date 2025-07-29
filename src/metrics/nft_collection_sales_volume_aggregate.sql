-- EXAMPLE QUERY: NFT collection sales volume (aggregate)

SELECT *
FROM ecosystem.nft_collection_sales_volume_aggregate(
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

-- CREATE TABLE: NFT collection sales volume (aggregate)

CREATE TABLE ecosystem._nft_collection_sales_volume_aggregate (
  token_id bigint,
  collection_name text,
  total bigint
);


-- CREATE FUNCTION: NFT collection sales volume (aggregate)

CREATE OR REPLACE FUNCTION ecosystem.nft_collection_sales_volume_aggregate(
  token_ids bigint[],
  start_ts bigint DEFAULT 0, 
  end_ts bigint DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000000000)::bigint
)
RETURNS SETOF ecosystem._nft_collection_sales_volume_aggregate
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
    WITH temp_tokens AS (
      SELECT DISTINCT unnest(token_ids) AS token_id
    ),
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
      t.name::text,
      COALESCE(s.total_tinybar, 0) AS total
    FROM 
      temp_tokens tt
      JOIN public.token t ON t.token_id = tt.token_id 
      LEFT JOIN sales s ON s.token_id = tt.token_id 
    ORDER BY 
      COALESCE(s.total_tinybar, 0) DESC;
END
$$;
