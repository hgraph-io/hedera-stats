# Plan — Add `day` Period to `avg_time_to_consensus`

## Objective

Produce a **daily** (`day`) series for `avg_time_to_consensus` using **Approach A**: duplicate the proven hourly Prometheus→ETL pipeline with `--step=1d`, minimal edits, and a simple daily cron. No SQL procedure changes are required—this ETL writes directly into `ecosystem.metric` via the existing bulk loader.

---

## Changes Overview

* New ETL scripts in `src/time-to-consensus/`:

  * `etl/extract_day.sh`
  * `etl/transform_day.sh`
  * `run_day.sh`
* System cron entry (keep hourly job intact)

---

## 1) Extract — `src/time-to-consensus/etl/extract_day.sh`

```bash
#!/usr/bin/env bash
set -eo pipefail

# Latest upper bound in nanoseconds for the daily series
LATEST_END_NS=$(psql "$POSTGRES_CONNECTION_STRING" -t -A -c \
  "select coalesce(max(upper(timestamp_range)), '0')::bigint
     from ecosystem.metric
    where name = 'avg_time_to_consensus'
      and period = 'day';")

LATEST_END_SEC=$((LATEST_END_NS / 1000000000))

# When empty, backfill by year to stay within Prometheus range limits
if [ "$LATEST_END_SEC" -eq 0 ]; then
  for i in {2023..2025}; do
    promtool query range \
      --format=json \
      --step=1d \
      --start="$i-01-01T00:00:00Z" \
      --end="$i-12-31T23:59:59Z" \
      "$PROMETHEUS_ENDPOINT" \
      'avg(platform_secC2RC{environment="mainnet"})'
  done
else
  # Continue from the end of the last interval, aligned to 00:00:00Z
  START_TIME=$(date --date="@$LATEST_END_SEC" -u +"%Y-%m-%dT00:00:00Z")
fi

END_TIME=$(date -u +"%Y-%m-%dT00:00:00Z")

if [[ -n "$START_TIME" && "$START_TIME" < "$END_TIME" ]]; then
  promtool query range \
    --format=json \
    --step=1d \
    --start="$START_TIME" \
    --end="$END_TIME" \
    "$PROMETHEUS_ENDPOINT" \
    'avg(platform_secC2RC{environment="mainnet"})'
fi
```

---

## 2) Transform — `src/time-to-consensus/etl/transform_day.sh`

```bash
#!/usr/bin/env bash
set -eo pipefail

# CSV header
echo '"name","period","timestamp_range","total"'

FILTER=$(cat <<'END'
.[0].values[] | [
  # lower bound in nanoseconds
  (.[0] | floor | tostring + "000000000"),
  # add one day (86400 seconds) for upper bound
  ((.[0] + 86400) | floor | tostring + "000000000"),
  # seconds → nanoseconds for the consensus time value
  (.[1] | tonumber * 1000000000 | floor)
] | [
  ("[" + .[0] + ", " + .[1] + ")"),
  .[2]
] | [
  "avg_time_to_consensus",
  "day",
  .[0],
  .[1]
] | @csv
END
)

jq --raw-output "$FILTER"
```

---

## 3) Loader (reuse) — `src/time-to-consensus/etl/load.sql`

*No change.* Continues to `COPY` into a temp table and `MERGE` into `ecosystem.metric`.

---

## 4) Runner — `src/time-to-consensus/run_day.sh`

```bash
#!/usr/bin/env bash
set -eo pipefail

# Load env and check deps (mirrors run.sh)
set -o allexport && source .env && set +o allexport

for VAR in PROMETHEUS_ENDPOINT POSTGRES_CONNECTION_STRING; do
  if [ -z "${!VAR+x}" ]; then
    echo "Missing $VAR"; exit 1
  fi
done

for CMD in psql jq; do
  command -v "$CMD" >/dev/null || { echo "Missing $CMD"; exit 1; }
done

DIR="$(dirname "$(realpath "$0")")"
"$DIR/etl/extract_day.sh" | tee "$DIR/.raw/data_day.json" | \
"$DIR/etl/transform_day.sh" | tee "$DIR/.raw/output_day.csv" | \
"$DIR/etl/load.sql"
```

> If `etl/load.sh` exists in your branch, pipe to that instead of `etl/load.sql` to stay consistent with your local setup. The SQL file is already idempotent.

---

## 5) Scheduling (system cron)

Keep the existing hourly job. Add a daily run at **00:02 UTC**:

```cron
# Time-to-consensus (daily)
2 0 * * * cd /path/to/hedera-stats/src/time-to-consensus && bash ./run_day.sh >> ./.raw/cron_day.log 2>&1
```

---

## 6) Validation

```sql
-- Confirm daily rows appear and are recent
select *
from ecosystem.metric
where name = 'avg_time_to_consensus'
  and period = 'day'
order by timestamp_range desc
limit 30;
```

```bash
# Prometheus sanity (3 days)
promtool query range --format=json --step=1d \
  --start="$(date -u -d '3 days ago' +'%Y-%m-%dT00:00:00Z')" \
  --end="$(date -u +'%Y-%m-%dT00:00:00Z')" \
  "$PROMETHEUS_ENDPOINT" \
  'avg(platform_secC2RC{environment="mainnet"})' | jq '.[0].values | length'
```

---

## Rollback

* Remove the daily cron line.
* Delete the three `_day` scripts if desired.
* Data is safe to keep; to purge:

```sql
delete from ecosystem.metric where name = 'avg_time_to_consensus' and period = 'day';
```

---

## Repo References (for validation)

* `ecosystem.avg_usd_conversion` function supports `'minute'` and limits to 100 candles; groups by `date_trunc(period, …)` and emits `(int8range, total)` rows.
* Existing init backfill for `avg_usd_conversion` (hour) to copy/tune for minute. 
* `ecosystem.metric` table schema & unique `(name, period, timestamp_range)` constraint.
* Hourly & daily loader procedures pattern for upsert and end-time truncation (mirrored in new minute proc).
* pg_cron scheduling patterns used in this repo. 
* Time-to-consensus ETL: `extract.sh` (`--step=1h`), `transform.sh` (+3600s upper), `run.sh` pipeline; our daily scripts are 1:1 adaptations.
