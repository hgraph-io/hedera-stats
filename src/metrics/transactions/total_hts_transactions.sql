-- Total HTS transactions
CREATE OR REPLACE FUNCTION ecosystem.total_hts_transactions (
  period TEXT,
  start_timestamp BIGINT DEFAULT 0,
  end_timestamp BIGINT DEFAULT (extract(epoch FROM current_timestamp) * 1e9)::BIGINT
)
RETURNS TABLE (int8range INT8RANGE, total BIGINT)
LANGUAGE SQL STABLE
AS $$
WITH all_entries AS (
  SELECT consensus_timestamp
  FROM public.transaction
  WHERE consensus_timestamp <= end_timestamp
    AND  type IN (29,31,32,33,34,35,36,37,38,39,40,41,45,46,47,53,57,58,59,60)
),
periodized AS (
  SELECT date_trunc(period, to_timestamp(consensus_timestamp / 1e9)) AS period_start,
         COUNT(*) AS new_in_period
  FROM all_entries
  GROUP BY 1
  ORDER BY 1
),
cumulative AS (
  SELECT
    period_start,
    SUM(new_in_period) OVER (ORDER BY period_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS total
  FROM periodized
)
SELECT int8range(
         (extract(epoch FROM period_start) * 1e9)::BIGINT,
         COALESCE(
           (extract(epoch FROM LEAD(period_start) OVER (ORDER BY period_start)) * 1e9)::BIGINT,
           end_timestamp
         )
       ) AS int8range,
       total
FROM cumulative
WHERE (extract(epoch FROM period_start) * 1e9) >= start_timestamp
  AND (extract(epoch FROM period_start) * 1e9) < end_timestamp
ORDER BY period_start;
$$;
