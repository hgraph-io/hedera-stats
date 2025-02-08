# Hedera stats

This repository is a collection of scripts and tools to gather and display statistics about the
Hedera network.


## Incremental update setup

Metrics:
- avg\_time\_to\_consensus

### 1. Install prometheus to use promtool cli

```bash
curl -o https://github.com/prometheus/prometheus/releases/download/v3.1.0/prometheus-3.1.0.linux-amd64.tar.gz
tar -xvf prometheus-3.1.0.linux-amd64.tar.gz
cd prometheus-3.1.0.linux-amd64
```

### 2. Add a cron job

```bash
crontab -e
0 * * * * bash /path/to/hedera-stats/time-to-consensus/run.sh >> ./cron.log 2>&1
```

### 3. Add the following line to run every hour

```bash
```
