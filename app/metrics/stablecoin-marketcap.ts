import { PoolClient } from 'pg';

interface StablecoinDataPoint {
  date: number;
  totalCirculating: { peggedUSD: number };
}

export async function fetchStablecoinMarketcap(
  client: PoolClient,
): Promise<void> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30_000);

  let data: StablecoinDataPoint[];
  try {
    const res = await fetch(
      'https://stablecoins.llama.fi/stablecoincharts/Hedera',
      { signal: controller.signal },
    );
    data = (await res.json()) as StablecoinDataPoint[];
  } catch (err: any) {
    console.warn(`stablecoin_marketcap fetch error: ${err.message}`);
    return;
  } finally {
    clearTimeout(timer);
  }

  if (!Array.isArray(data) || data.length === 0) {
    console.warn('stablecoin_marketcap: no data from DeFiLlama');
    return;
  }

  await client.query('BEGIN');
  try {
    await client.query(`
      CREATE TEMP TABLE temp_stablecoin (
        date_sec numeric,
        marketcap numeric
      ) ON COMMIT DROP
    `);

    const dates = data.map((d) => String(d.date));
    const caps = data.map((d) =>
      String(d.totalCirculating?.peggedUSD ?? 0),
    );
    await client.query(
      `INSERT INTO temp_stablecoin (date_sec, marketcap)
       SELECT * FROM unnest($1::numeric[], $2::numeric[])`,
      [dates, caps],
    );

    // Matches the original src/jobs/stablecoin_marketcap.sql logic
    await client.query(`
      INSERT INTO ecosystem.metric (name, period, timestamp_range, total)
      SELECT 'stablecoin_marketcap', 'day',
        int8range(
          (to_timestamp(date_sec))::timestamp9::bigint,
          (to_timestamp(date_sec) + '1 day'::interval)::timestamp9::bigint
        ),
        marketcap
      FROM temp_stablecoin
      ON CONFLICT (name, period, timestamp_range) DO UPDATE SET total = EXCLUDED.total
    `);

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  }
}
