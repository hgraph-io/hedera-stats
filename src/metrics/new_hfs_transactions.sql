-- New HFS transactions
CREATE OR REPLACE FUNCTION ecosystem.new_hfs_transactions (
  period TEXT,
  start_timestamp BIGINT DEFAULT 0,
  end_timestamp BIGINT DEFAULT (extract(epoch FROM current_timestamp) * 1e9)::BIGINT
)
RETURNS TABLE (timestamp_range INT8RANGE, total BIGINT)
LANGUAGE SQL STABLE
AS $$
WITH all_entries AS (
  SELECT consensus_timestamp
  FROM   public.transaction
  WHERE  consensus_timestamp BETWEEN start_timestamp AND end_timestamp
    AND  type IN (16,17,18,19)
),
periodized AS (
  SELECT date_trunc(period,
                    to_timestamp(consensus_timestamp / 1e9)) AS period_start,
         COUNT(*) AS total
  FROM   all_entries
  GROUP  BY 1
  ORDER  BY 1
)
SELECT int8range(
         (extract(epoch FROM period_start) * 1e9)::BIGINT,
         COALESCE(
           (extract(epoch FROM LEAD(period_start) OVER (ORDER BY period_start)) * 1e9)::BIGINT,
           end_timestamp + 1
         )
       ) AS timestamp_range,
       total
FROM periodized;
$$;
