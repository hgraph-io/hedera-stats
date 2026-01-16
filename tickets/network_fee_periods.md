# Ticket: Add Week/Month/Quarter/Year Periods to `network_fee`

## Summary

Enable `network_fee` metric for weekly, monthly, quarterly, and yearly aggregation periods.

## Background

The `network_fee` function already supports all periods via its `period TEXT` parameter. It currently runs for `hour` and `day` periods but is not registered in the week/month/quarter/year job loaders.

## Current State

| Period | Job File | Included |
|--------|----------|----------|
| hour | `load_metrics_hour.sql` | Yes (line 21) |
| day | `load_metrics_day.sql` | Yes (line 25) |
| week | `load_metrics_week.sql` | No |
| month | `load_metrics_month.sql` | No |
| quarter | `load_metrics_quarter.sql` | No |
| year | `load_metrics_year.sql` | No |

## Implementation

No function changes required. Add `'network_fee'` to the metrics array in each job loader.

## Files to Modify

| File | Change |
|------|--------|
| `src/jobs/load_metrics_week.sql` | Add `'network_fee'` to metrics array |
| `src/jobs/load_metrics_month.sql` | Add `'network_fee'` to metrics array |
| `src/jobs/load_metrics_quarter.sql` | Add `'network_fee'` to metrics array |
| `src/jobs/load_metrics_year.sql` | Add `'network_fee'` to metrics array |
| `CHANGELOG.md` | Add entry under Unreleased |

## Suggested Placement

Add after the existing metrics that share similar patterns. Recommended position: after `'hbar_market_cap'` to keep network performance metrics grouped.

```sql
metrics constant text[] := array[
    ...
    'hbar_market_cap',
    'network_fee',  -- ADD HERE
    'active_developer_accounts',
    ...
];
```

## Acceptance Criteria

- [ ] `'network_fee'` added to `load_metrics_week.sql`
- [ ] `'network_fee'` added to `load_metrics_month.sql`
- [ ] `'network_fee'` added to `load_metrics_quarter.sql`
- [ ] `'network_fee'` added to `load_metrics_year.sql`
- [ ] CHANGELOG.md updated
- [ ] Data populates in `ecosystem.metric` for all new periods after jobs run

## Backfilling Historical Data

To backfill historical data for the new periods, use `src/jobs/load_metrics_init.sql`. Configure the `periods` and `metrics` arrays in the procedure, then execute it to populate data from the beginning of time up to the current hour.

## Validation

After deployment, verify data exists:

```sql
SELECT period, COUNT(*), MIN(lower(timestamp_range))::timestamp9::timestamp, MAX(upper(timestamp_range))::timestamp9::timestamp
FROM ecosystem.metric
WHERE name = 'network_fee'
GROUP BY period
ORDER BY period;
```

Expected: rows for hour, day, week, month, quarter, year.
