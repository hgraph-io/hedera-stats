import { PoolClient } from 'pg';

interface TvlDataPoint {
  date: number;
  tvl: number;
}

export async function fetchNetworkTvl(client: PoolClient): Promise<void> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30_000);

  let data: TvlDataPoint[];
  try {
    const res = await fetch(
      'https://api.llama.fi/v2/historicalChainTvl/Hedera',
      { signal: controller.signal },
    );
    data = (await res.json()) as TvlDataPoint[];
  } catch (err: any) {
    console.warn(`network_tvl fetch error: ${err.message}`);
    return;
  } finally {
    clearTimeout(timer);
  }

  if (!Array.isArray(data) || data.length === 0) {
    console.warn('network_tvl: no data from DeFiLlama');
    return;
  }

  await client.query('BEGIN');
  try {
    await client.query(`
      CREATE TEMP TABLE temp_tvl (
        date_sec numeric,
        tvl numeric
      ) ON COMMIT DROP
    `);

    const dates = data.map((d) => String(d.date));
    const tvls = data.map((d) => String(d.tvl));
    await client.query(
      `INSERT INTO temp_tvl (date_sec, tvl)
       SELECT * FROM unnest($1::numeric[], $2::numeric[])`,
      [dates, tvls],
    );

    // Matches the original src/jobs/network_tvl.sql logic
    await client.query(`
      INSERT INTO ecosystem.metric (name, period, timestamp_range, total)
      SELECT 'network_tvl', 'day',
        int8range(
          (to_timestamp(date_sec))::timestamp9::bigint,
          (to_timestamp(date_sec) + '1 day'::interval)::timestamp9::bigint
        ),
        tvl
      FROM temp_tvl
      ON CONFLICT (name, period, timestamp_range) DO UPDATE SET total = EXCLUDED.total
    `);

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  }
}
