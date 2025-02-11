# Hedera stats

This repository is a collection of scripts and tools to gather and display statistics about the
Hedera network.


## Incremental update setup

Metrics:
- avg\_time\_to\_consensus

### 1. Install prometheus to use promtool cli

```bash
curl -L -O https://github.com/prometheus/prometheus/releases/download/v3.1.0/prometheus-3.1.0.linux-amd64.tar.gz
tar -xvf prometheus-3.1.0.linux-amd64.tar.gz
# one way to add the tool to the PATH
cp prometheus-3.1.0.linux-amd64/promtool /usr/bin
```

### 2. Add a cron job

```bash
crontab -e
1 * * * * cd /path/to/hedera-stats/src/time-to-consensus && bash ./run.sh >> ./.raw/cron.log 2>&1
```
