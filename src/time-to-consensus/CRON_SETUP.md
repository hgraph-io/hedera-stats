# Cron Setup for Time-to-Consensus ETL

## Current Jobs

### Hourly Collection
The existing hourly collection job should remain unchanged.

### Daily Collection (NEW)

Add the following entry to your system cron to run daily collection at 00:02 UTC:

```bash
# Time-to-consensus (daily)
2 0 * * * cd /path/to/hedera-stats/src/time-to-consensus && bash ./run_day.sh >> ./.raw/cron_day.log 2>&1
```

**Important Notes:**
- Replace `/path/to/hedera-stats` with the actual path to your repository
- The job runs at 00:02 UTC (2 minutes after midnight) to avoid conflicts with hourly collection
- Logs are written to `.raw/cron_day.log` for debugging
- Ensure the `.env` file exists in the time-to-consensus directory with proper credentials

## Validation

After setup, verify the daily data is being collected:

```sql
-- Check recent daily data
SELECT *
FROM ecosystem.metric
WHERE name = 'avg_time_to_consensus'
  AND period = 'day'
ORDER BY timestamp_range DESC
LIMIT 10;
```