# Hedera stats

This repository is a collection of scripts and tools to gather and display statistics about the
Hedera network.


## Incremental update setup

Metrics:
- avg_time_to_consensus

### 1. Open the crontab editor
```bash
crontab -e
```

### 2. Add the following line to run every hour
```bash
0 * * * * cd /path/to/hedera-stats/time-to-consensus && ./run_incremental.sh >> ./cron.log 2>&1
```
