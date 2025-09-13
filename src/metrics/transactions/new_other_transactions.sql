-- New Other transactions
CREATE OR REPLACE FUNCTION ecosystem.new_other_transactions (
  period TEXT,
  start_timestamp BIGINT DEFAULT 0,
  end_timestamp BIGINT DEFAULT (extract(epoch FROM current_timestamp) * 1e9)::BIGINT
)
RETURNS TABLE (int8range INT8RANGE, total BIGINT)
LANGUAGE SQL STABLE
AS $$
WITH all_entries AS (
  SELECT consensus_timestamp
  FROM   public.transaction
  WHERE  consensus_timestamp BETWEEN start_timestamp AND end_timestamp
    AND  type IN (20,21,23,28,42,43,44,51,52,54,55,56,65)
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
           end_timestamp
         )
       ) AS int8range,
       total
FROM periodized
WHERE (extract(epoch FROM period_start) * 1e9) >= start_timestamp
  AND (extract(epoch FROM period_start) * 1e9) < end_timestamp;
$$;
