import { Pool } from 'pg';
import { JobDef, KNOWN_SQL_METRICS } from './registry';
import { fetchAvgUsdConversion } from './metrics/avg-usd-conversion';
import { fetchNetworkTvl } from './metrics/network-tvl';
import { fetchStablecoinMarketcap } from './metrics/stablecoin-marketcap';

// Validate metric name is a known identifier (prevent SQL injection)
function assertKnownMetric(name: string): void {
  if (!/^[a-z_]+$/.test(name)) {
    throw new Error(`Invalid metric name: ${name}`);
  }
}

async function runSqlMetric(
  pool: Pool,
  metricName: string,
  period: string,
  endTimestamp: string,
): Promise<void> {
  assertKnownMetric(metricName);
  const client = await pool.connect();
  try {
    await client.query('SET search_path TO ecosystem, public');

    // Get last known timestamp for this metric/period
    const lastTs = await client.query(
      `SELECT COALESCE(MAX(UPPER(timestamp_range)), 0::bigint)::text AS ts
       FROM ecosystem.metric WHERE period = $1 AND name = $2`,
      [period, metricName],
    );
    const startTimestamp = lastTs.rows[0].ts;

    // Call metric function and upsert results
    // Using string interpolation for the function name is safe because
    // we validate metricName above (alphanumeric + underscore only)
    await client.query(
      `INSERT INTO ecosystem.metric (name, period, timestamp_range, total)
       SELECT $1 AS name, $2 AS period, int8range AS timestamp_range, total
       FROM ecosystem.${metricName}($2::text, $3::bigint, $4::bigint)
       WHERE upper(int8range) IS NOT NULL
       ON CONFLICT (name, period, timestamp_range) DO UPDATE SET total = EXCLUDED.total`,
      [metricName, period, startTimestamp, endTimestamp],
    );
  } finally {
    client.release();
  }
}

async function runApiMetric(
  pool: Pool,
  metricName: string,
  period: string,
  endTimestamp: string,
): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('SET search_path TO ecosystem, public');

    // Get last known timestamp
    const lastTs = await client.query(
      `SELECT COALESCE(MAX(UPPER(timestamp_range)), 0::bigint)::text AS ts
       FROM ecosystem.metric WHERE period = $1 AND name = $2`,
      [period, metricName],
    );
    const startTimestamp = lastTs.rows[0].ts;

    switch (metricName) {
      case 'avg_usd_conversion':
        await fetchAvgUsdConversion(client, period, startTimestamp, endTimestamp);
        break;
      case 'network_tvl':
        await fetchNetworkTvl(client);
        break;
      case 'stablecoin_marketcap':
        await fetchStablecoinMarketcap(client);
        break;
      default:
        console.warn(`Unknown API metric: ${metricName}`);
    }
  } finally {
    client.release();
  }
}

export async function runJob(pool: Pool, job: JobDef): Promise<void> {
  const startTime = Date.now();
  let processed = 0;
  const errors: Array<{ metric: string; error: string }> = [];

  // Calculate end timestamp via SQL (uses timestamp9 for consistency)
  const client = await pool.connect();
  let endTimestamp: string;
  try {
    await client.query('SET search_path TO ecosystem, public');
    const res = await client.query(
      `SELECT date_trunc($1, now())::timestamp9::bigint::text AS end_ts`,
      [job.truncation],
    );
    endTimestamp = res.rows[0].end_ts;
  } finally {
    client.release();
  }

  console.log(
    `[${job.name}] Starting job - ${job.metrics.length} metrics, period=${job.period}`,
  );

  for (const metric of job.metrics) {
    try {
      if (metric.type === 'sql') {
        await runSqlMetric(pool, metric.name, job.period, endTimestamp);
      } else {
        await runApiMetric(pool, metric.name, job.period, endTimestamp);
      }
      processed++;
    } catch (err: any) {
      errors.push({ metric: metric.name, error: err.message });
      console.warn(
        `[${job.name}] Failed metric ${metric.name}: ${err.message}`,
      );
    }
  }

  // Retention cleanup
  if (job.retention) {
    try {
      const retClient = await pool.connect();
      try {
        await retClient.query('SET search_path TO ecosystem, public');
        await retClient.query(
          `DELETE FROM ecosystem.metric
           WHERE name = $1 AND period = $2
             AND upper(timestamp_range) < (date_trunc($2, now() - ($3 || ' hours')::interval))::timestamp9::bigint`,
          [job.retention.metricName, job.period, String(job.retention.hours)],
        );
      } finally {
        retClient.release();
      }
    } catch (err: any) {
      console.warn(`[${job.name}] Retention cleanup failed: ${err.message}`);
    }
  }

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log(
    `[${job.name}] Done - ${processed}/${job.metrics.length} metrics, ${errors.length} errors, ${elapsed}s`,
  );
  if (errors.length > 0) {
    console.log(`[${job.name}] Errors:`, JSON.stringify(errors));
  }
}
