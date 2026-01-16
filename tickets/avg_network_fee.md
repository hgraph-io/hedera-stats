# Ticket: Add `avg_network_fee` Metric

## Summary

Add a new network performance metric to track the average transaction fee on Hedera.

## Metric Details

| Property | Value |
|----------|-------|
| Name | `avg_network_fee` |
| Category | Network Performance |
| Periods | `hour`, `day` |
| Unit | tinybars (bigint) |

## Description

Measures the average transaction fee charged on the Hedera network within a given period.

## Methodology

Calculates the average of all `charged_tx_fee` values from the transaction table during the period. Stored in tinybars (divide by 10^8 for HBAR).

## Data Source

- **Table:** `public.transaction`
- **Field:** `charged_tx_fee` (bigint)
- **Scope:** All transactions in period

## Implementation

### Function Signature

```sql
create or replace function ecosystem.avg_network_fee(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
) returns setof ecosystem.metric_total
```

### SQL Pattern (mirrors network_fee.sql exactly, only line 18 differs)

```sql
create or replace function ecosystem.avg_network_fee(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem.metric_total
as $$
with transactions_fee as (
        select
            consensus_timestamp,
            charged_tx_fee
        from public.transaction
        where consensus_timestamp between start_timestamp and end_timestamp
    ),
avg_fee_per_period as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
        (sum(charged_tx_fee) / count(*))::bigint as total  -- Only change: SUM/COUNT instead of SUM
    from transactions_fee
    group by 1
    order by 1 desc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        coalesce((lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint, end_timestamp)
    ),
    total
from avg_fee_per_period
$$ language sql stable;
```

**Verified via MCP (Hgraph)**: For hour 18:00-19:00 UTC on 2026-01-06:
- sum_fee: 52,422,715,461 tinybars (matches `network_fee` metric)
- tx_count: 21,516 (matches `new_transactions` metric)
- avg_fee: **2,436,453 tinybars** (~0.024 HBAR)

## Files to Modify

| File | Change |
|------|--------|
| `src/metrics/network-performance/avg_network_fee.sql` | Create new function |
| `src/metric_descriptions.sql` | Add description entry (line ~13, after `network_tps`) |
| `src/jobs/load_metrics_hour.sql` | Add `'avg_network_fee'` after `'network_fee'` (line 22) |
| `src/jobs/load_metrics_day.sql` | Add `'avg_network_fee'` after `'network_fee'` (line 26) |
| `CHANGELOG.md` | Add entry under Unreleased |

## Suggested Placement

### metric_descriptions.sql (after network_tps, line 13)

```sql
    ('avg_network_fee', 'Measures the average transaction fee charged on the Hedera network within a given period.', 'Calculates the average of all charged_tx_fee values from the transaction table during the period. Stored in tinybars (divide by 10^8 for HBAR).'),
```

### load_metrics_hour.sql (after network_fee, line 22)

```sql
        'network_fee',
        'avg_network_fee',
        'network_tps',
```

### load_metrics_day.sql (after network_fee, line 26)

```sql
        'network_fee',
        'avg_network_fee',
        'network_tps',
```

## Backfilling Historical Data

To backfill historical data for this metric, use `src/jobs/load_metrics_init.sql`. Configure the `periods` and `metrics` arrays in the procedure, then execute it to populate data from the beginning of time up to the current hour.

## Acceptance Criteria

- [ ] Function `ecosystem.avg_network_fee()` created and returns valid data
- [ ] Metric description added to `ecosystem.metric_description`
- [ ] Hourly job includes `avg_network_fee` in metrics array
- [ ] Daily job includes `avg_network_fee` in metrics array
- [ ] Data populates in `ecosystem.metric` table
- [ ] CHANGELOG.md updated

## Validation

Test function directly:

```sql
SELECT * FROM ecosystem.avg_network_fee('hour', 0, CURRENT_TIMESTAMP::timestamp9::bigint) LIMIT 5;
```

Verify data in metric table after job runs:

```sql
SELECT name, period, timestamp_range, total
FROM ecosystem.metric
WHERE name = 'avg_network_fee'
ORDER BY timestamp_range DESC
LIMIT 10;
```

## References

- Related metric: `network_fee` (sum of fees)
- Data source: Hedera mirror node `transaction.charged_tx_fee`
- Typical values: ~1-3 million tinybars (~0.01-0.03 HBAR per transaction)
