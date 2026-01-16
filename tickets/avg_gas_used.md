# Ticket: Add `avg_gas_used` Metric

## Summary

Add a new EVM metric to track the average gas consumed per transaction on Hedera.

## Metric Details

| Property | Value |
|----------|-------|
| Name | `avg_gas_used` |
| Category | EVM |
| Period | `hour` |
| Unit | Gas units (bigint) |

## Description

Average gas consumed per EVM transaction within a given time period.

## Methodology

Calculates the average of `gas_used` from the `contract_result` table for all transactions where `gas_used > 0`, grouped by period and cast to bigint.

## Data Source

- **Table:** `contract_result`
- **Field:** `gas_used` (bigint, NOT NULL)
- **Filter:** `gas_used > 0`
- **Scope:** All EVM transactions (success and failure)

## Implementation

### Function Signature

```sql
CREATE OR REPLACE FUNCTION ecosystem.avg_gas_used(
    period TEXT,
    start_timestamp BIGINT DEFAULT 0,
    end_timestamp BIGINT DEFAULT CURRENT_TIMESTAMP::timestamp9::BIGINT
) RETURNS SETOF ecosystem.metric_total
```

### SQL Pattern

```sql
WITH gas_per_period AS (
    SELECT
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) AS period_start_timestamp,
        AVG(gas_used)::BIGINT AS total
    FROM contract_result
    WHERE consensus_timestamp BETWEEN start_timestamp AND end_timestamp
      AND gas_used > 0
    GROUP BY period_start_timestamp
)
SELECT
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (LEAD(period_start_timestamp) OVER (ORDER BY period_start_timestamp))::timestamp9::bigint
    ),
    total
FROM gas_per_period
```

## Files to Modify

| File | Change |
|------|--------|
| `src/metrics/evm/avg_gas_used.sql` | Create new function |
| `src/metric_descriptions.sql` | Add description entry |
| `src/jobs/load_metrics_hour.sql` | Add `'avg_gas_used'` to metrics array |
| `CHANGELOG.md` | Add entry under Unreleased |

## Backfilling Historical Data

To backfill historical data for this metric, use `src/jobs/load_metrics_init.sql`. Configure the `periods` and `metrics` arrays in the procedure, then execute it to populate data from the beginning of time up to the current hour.

## Validation

Sample data (via Hgraph):
- Average: ~69,704 gas units
- Range: 2,607 - 8,400,000
- Coverage: ~98.5% of `contract_result` records have `gas_used > 0`

## Acceptance Criteria

- [ ] Function `ecosystem.avg_gas_used()` created and returns valid data
- [ ] Metric description added to `ecosystem.metric_description`
- [ ] Hourly job includes `avg_gas_used` in metrics array
- [ ] Data populates in `ecosystem.metric` table
- [ ] CHANGELOG.md updated

## References

- Similar metrics: `network_tps`, `active_smart_contracts`
- Data source: Hedera mirror node `contract_result` table
