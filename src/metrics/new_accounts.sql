CREATE OR REPLACE FUNCTION ecosystem.new_accounts (
  period             public.interval_granularity,
  start_timestamp    BIGINT DEFAULT 0, 
  end_timestamp      BIGINT DEFAULT
    (extract(epoch FROM current_timestamp) * 1e9)::BIGINT
)
RETURNS TABLE (timestamp_range INT8RANGE, total BIGINT)
LANGUAGE SQL STABLE
AS $$
WITH all_entries AS (
  SELECT created_timestamp
  FROM public.entity
  WHERE type = 'ACCOUNT'
    AND created_timestamp BETWEEN start_timestamp AND end_timestamp
    AND key IS NOT NULL
    AND encode(key, 'hex') <> '3200'
),
periodized AS (
  SELECT
    date_trunc(period::TEXT,
               to_timestamp(created_timestamp / 1e9)) AS period_start,
    COUNT(*) AS total
  FROM all_entries
  GROUP BY 1
  ORDER BY 1
)
SELECT
  int8range(
    (extract(epoch FROM period_start) * 1e9)::BIGINT,
    COALESCE(
      (extract(epoch FROM LEAD(period_start) OVER (ORDER BY period_start)) * 1e9)::BIGINT,
      end_timestamp + 1 
    )
  ) AS timestamp_range,
  total
FROM periodized;
$$;
