CREATE OR REPLACE FUNCTION ecosystem.active_accounts(
    period TEXT,
    start_timestamp BIGINT DEFAULT 0,
    end_timestamp   BIGINT DEFAULT CURRENT_TIMESTAMP::timestamp9::BIGINT
)
RETURNS SETOF ecosystem.metric_total
AS $$
WITH active_accounts AS (
    SELECT * FROM ecosystem.active_developer_accounts(period, start_timestamp, end_timestamp)
    UNION ALL
    SELECT * FROM ecosystem.active_retail_accounts  (period, start_timestamp, end_timestamp)
    UNION ALL
    SELECT * FROM ecosystem.active_smart_contracts  (period, start_timestamp, end_timestamp)
),
merged_data AS (
    SELECT
        DATE_TRUNC(
            period,
            (LOWER(int8range))::timestamp9::timestamp
        )                         AS period_start,
        SUM(total)                AS total
    FROM   active_accounts
    GROUP  BY 1
)
SELECT
    INT8RANGE(
        period_start::timestamp9::BIGINT,
        (CASE period
            WHEN 'hour'    THEN period_start + INTERVAL '1 hour'
            WHEN 'day'     THEN period_start + INTERVAL '1 day'
            WHEN 'week'    THEN period_start + INTERVAL '1 week'
            WHEN 'month'   THEN period_start + INTERVAL '1 month'
            WHEN 'quarter' THEN period_start + INTERVAL '3 months'
            WHEN 'year'    THEN period_start + INTERVAL '1 year'
            ELSE period_start + INTERVAL '1 day'
         END)::timestamp9::BIGINT
    ),
    total
FROM   merged_data
WHERE  (
        CASE period
          WHEN 'hour'    THEN period_start + INTERVAL '1 hour'
          WHEN 'day'     THEN period_start + INTERVAL '1 day'
          WHEN 'week'    THEN period_start + INTERVAL '1 week'
          WHEN 'month'   THEN period_start + INTERVAL '1 month'
          WHEN 'quarter' THEN period_start + INTERVAL '3 months'
          WHEN 'year'    THEN period_start + INTERVAL '1 year'
          ELSE period_start + INTERVAL '1 day'
        END
       ) <= CURRENT_TIMESTAMP 
ORDER  BY period_start DESC;
$$ LANGUAGE sql STABLE;
