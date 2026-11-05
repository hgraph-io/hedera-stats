-- 107-light_totals_quarter_interval.sql — make the light total_transactions,
-- total_crypto_transactions and total_hcs_transactions functions work at
-- period = 'quarter'.
--
-- 049/059/066 step generate_series by ('1 ' || period)::interval. '1 quarter' is
-- not valid interval syntax (date_trunc accepts 'quarter', interval input does
-- not), so every quarter call raised, the loaders' per-metric exception handler
-- swallowed it, and these three quarter series stopped advancing. Quarter now
-- steps by '3 months'; every other period is unchanged.
--
-- The prior-total lookup's `m.period = period` is left as is: a column name wins
-- over a same-named parameter, so it matches rows of every period. That is what
-- seeds a series with no rows yet at this period (testnet has no quarter rows) from
-- the day/hour cumulative total; a cumulative total at a timestamp is the same
-- whatever period stored it.
--
-- Bodies are otherwise 049/059/066 verbatim.

BEGIN;

CREATE OR REPLACE FUNCTION ecosystem.total_transactions (
  period TEXT,
  start_timestamp BIGINT DEFAULT 0,
  end_timestamp   BIGINT DEFAULT (extract(epoch FROM current_timestamp) * 1e9)::BIGINT
)
RETURNS TABLE (int8range INT8RANGE, total BIGINT)
LANGUAGE SQL STABLE
AS $$
WITH prior AS (
  -- Last persisted cumulative total at/before start_timestamp
  SELECT COALESCE(
           (SELECT m.total
            FROM ecosystem.metric m
            WHERE m.name = 'total_transactions'
              AND m.period = period
              AND upper(m.timestamp_range) <= start_timestamp
            ORDER BY upper(m.timestamp_range) DESC
            LIMIT 1),
           0
         ) AS base_total
),
all_entries AS (
  SELECT date_trunc(period, to_timestamp(t.consensus_timestamp / 1e9)) AS period_start,
         COUNT(*) AS new_in_period
  FROM public.transaction t
  WHERE t.consensus_timestamp >= start_timestamp
    AND t.consensus_timestamp <  end_timestamp
  GROUP BY 1
),
period_series AS (
  -- Generate all period boundaries between start and end
  SELECT generate_series(
           date_trunc(period, to_timestamp(start_timestamp / 1e9)),
           date_trunc(period, to_timestamp(end_timestamp   / 1e9)),
           CASE period WHEN 'quarter' THEN interval '3 months' ELSE ('1 ' || period)::interval END
         ) AS period_start
),
joined AS (
  SELECT s.period_start,
         COALESCE(a.new_in_period, 0) AS new_in_period
  FROM period_series s
  LEFT JOIN all_entries a USING (period_start)
),
incremental AS (
  SELECT
    period_start,
    (SELECT base_total FROM prior)
      + SUM(new_in_period) OVER (ORDER BY period_start) AS total
  FROM joined
)
SELECT int8range(
         (extract(epoch FROM period_start) * 1e9)::BIGINT,
         COALESCE(
           (extract(epoch FROM LEAD(period_start) OVER (ORDER BY period_start)) * 1e9)::BIGINT,
           end_timestamp
         )
       ) AS int8range,
       total
FROM incremental
WHERE (extract(epoch FROM period_start) * 1e9) >= start_timestamp
  AND (extract(epoch FROM period_start) * 1e9) <  end_timestamp
ORDER BY period_start;
$$;

CREATE OR REPLACE FUNCTION ecosystem.total_crypto_transactions (
  period TEXT,
  start_timestamp BIGINT DEFAULT 0,
  end_timestamp   BIGINT DEFAULT (extract(epoch FROM current_timestamp) * 1e9)::BIGINT
)
RETURNS TABLE (int8range INT8RANGE, total BIGINT)
LANGUAGE SQL STABLE
AS $$
WITH prior AS (
  SELECT COALESCE(
           (SELECT m.total
            FROM ecosystem.metric m
            WHERE m.name = 'total_crypto_transactions'
              AND m.period = period
              AND upper(m.timestamp_range) <= start_timestamp
            ORDER BY upper(m.timestamp_range) DESC
            LIMIT 1),
           0
         ) AS base_total
),
all_entries AS (
  SELECT date_trunc(period, to_timestamp(t.consensus_timestamp / 1e9)) AS period_start,
         COUNT(*) AS new_in_period
  FROM public.transaction t
  WHERE t.consensus_timestamp >= start_timestamp
    AND t.consensus_timestamp <  end_timestamp
    AND t.type IN (10, 11, 12, 13, 14, 15, 48, 49)
  GROUP BY 1
),
period_series AS (
  SELECT generate_series(
           date_trunc(period, to_timestamp(start_timestamp / 1e9)),
           date_trunc(period, to_timestamp(end_timestamp   / 1e9)),
           CASE period WHEN 'quarter' THEN interval '3 months' ELSE ('1 ' || period)::interval END
         ) AS period_start
),
joined AS (
  SELECT s.period_start,
         COALESCE(a.new_in_period, 0) AS new_in_period
  FROM period_series s
  LEFT JOIN all_entries a USING (period_start)
),
incremental AS (
  SELECT
    period_start,
    (SELECT base_total FROM prior)
      + SUM(new_in_period) OVER (ORDER BY period_start) AS total
  FROM joined
)
SELECT int8range(
         (extract(epoch FROM period_start) * 1e9)::BIGINT,
         COALESCE(
           (extract(epoch FROM LEAD(period_start) OVER (ORDER BY period_start)) * 1e9)::BIGINT,
           end_timestamp
         )
       ) AS int8range,
       total
FROM incremental
WHERE (extract(epoch FROM period_start) * 1e9) >= start_timestamp
  AND (extract(epoch FROM period_start) * 1e9) <  end_timestamp
ORDER BY period_start;
$$;

CREATE OR REPLACE FUNCTION ecosystem.total_hcs_transactions (
  period TEXT,
  start_timestamp BIGINT DEFAULT 0,
  end_timestamp   BIGINT DEFAULT (extract(epoch FROM current_timestamp) * 1e9)::BIGINT
)
RETURNS TABLE (int8range INT8RANGE, total BIGINT)
LANGUAGE SQL STABLE
AS $$
WITH prior AS (
  SELECT COALESCE(
           (SELECT m.total
            FROM ecosystem.metric m
            WHERE m.name = 'total_hcs_transactions'
              AND m.period = period
              AND upper(m.timestamp_range) <= start_timestamp
            ORDER BY upper(m.timestamp_range) DESC
            LIMIT 1),
           0
         ) AS base_total
),
all_entries AS (
  SELECT date_trunc(period, to_timestamp(t.consensus_timestamp / 1e9)) AS period_start,
         COUNT(*) AS new_in_period
  FROM public.transaction t
  WHERE t.consensus_timestamp >= start_timestamp
    AND t.consensus_timestamp <  end_timestamp
    AND t.type IN (27, 28, 29)
  GROUP BY 1
),
period_series AS (
  SELECT generate_series(
           date_trunc(period, to_timestamp(start_timestamp / 1e9)),
           date_trunc(period, to_timestamp(end_timestamp   / 1e9)),
           CASE period WHEN 'quarter' THEN interval '3 months' ELSE ('1 ' || period)::interval END
         ) AS period_start
),
joined AS (
  SELECT s.period_start,
         COALESCE(a.new_in_period, 0) AS new_in_period
  FROM period_series s
  LEFT JOIN all_entries a USING (period_start)
),
incremental AS (
  SELECT
    period_start,
    (SELECT base_total FROM prior)
      + SUM(new_in_period) OVER (ORDER BY period_start) AS total
  FROM joined
)
SELECT int8range(
         (extract(epoch FROM period_start) * 1e9)::BIGINT,
         COALESCE(
           (extract(epoch FROM LEAD(period_start) OVER (ORDER BY period_start)) * 1e9)::BIGINT,
           end_timestamp
         )
       ) AS int8range,
       total
FROM incremental
WHERE (extract(epoch FROM period_start) * 1e9) >= start_timestamp
  AND (extract(epoch FROM period_start) * 1e9) <  end_timestamp
ORDER BY period_start;
$$;

COMMIT;
