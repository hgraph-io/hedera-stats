import { PoolClient } from 'pg';

interface CandleData {
  openTimeMs: number;
  closePrice: number;
}

function getExchangeIntervals(period: string) {
  switch (period) {
    case 'month':
      return { binance: '1M', okx: '1Mutc', bitget: '1Mutc', mexc: '1M' };
    case 'week':
      return { binance: '1w', okx: '1Wutc', bitget: '1Wutc', mexc: '1W' };
    case 'day':
      return { binance: '1d', okx: '1Dutc', bitget: '1Dutc', mexc: '1d' };
    case 'hour':
      return { binance: '1h', okx: '1H', bitget: '1h', mexc: '60m' };
    case 'minute':
      return { binance: '1m', okx: '1m', bitget: '1min', mexc: '1m' };
    default:
      return { binance: '1M', okx: '1Mutc', bitget: '1Mutc', mexc: '1M' };
  }
}

function getPeriodMs(period: string): number {
  switch (period) {
    case 'minute': return 60_000;
    case 'hour': return 3_600_000;
    case 'day': return 86_400_000;
    case 'week': return 604_800_000;
    case 'month': return 2_592_000_000; // ~30 days
    default: return 2_592_000_000;
  }
}

async function fetchJson(url: string, timeoutMs = 10_000): Promise<any> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

async function fetchBinance(
  interval: string, startMs: number, endMs: number, limit: number,
): Promise<CandleData[]> {
  try {
    const url =
      `https://data-api.binance.vision/api/v3/klines` +
      `?symbol=HBARUSDT&interval=${interval}` +
      `&startTime=${startMs}&endTime=${endMs}&limit=${limit}`;
    const data = await fetchJson(url);
    if (!Array.isArray(data)) return [];
    return data.map((c: any[]) => ({
      openTimeMs: Number(c[0]),
      closePrice: Number(c[4]),
    }));
  } catch (err: any) {
    console.warn(`Binance fetch error: ${err.message}`);
    return [];
  }
}

async function fetchOkx(
  bar: string, startMs: number, endMs: number, limit: number,
): Promise<CandleData[]> {
  try {
    const url =
      `https://www.okx.com/api/v5/market/history-index-candles` +
      `?instId=HBAR-USDT&bar=${bar}` +
      `&before=${startMs}&after=${endMs}&limit=${limit}`;
    const data = await fetchJson(url);
    if (!data?.data || !Array.isArray(data.data)) return [];
    return data.data.map((c: any[]) => ({
      openTimeMs: Number(c[0]),
      closePrice: Number(c[4]),
    }));
  } catch (err: any) {
    console.warn(`OKX fetch error: ${err.message}`);
    return [];
  }
}

async function fetchBitget(
  granularity: string, startMs: number, endMs: number, limit: number,
): Promise<CandleData[]> {
  try {
    const url =
      `https://api.bitget.com/api/v2/spot/market/candles` +
      `?symbol=HBARUSDT&granularity=${granularity}` +
      `&startTime=${startMs}&endTime=${endMs}&limit=${limit}`;
    const data = await fetchJson(url);
    if (!data?.data || !Array.isArray(data.data)) return [];
    return data.data.map((c: any[]) => ({
      openTimeMs: Number(c[0]),
      closePrice: Number(c[4]),
    }));
  } catch (err: any) {
    console.warn(`Bitget fetch error: ${err.message}`);
    return [];
  }
}

async function fetchMexc(
  interval: string, startMs: number, endMs: number, limit: number,
): Promise<CandleData[]> {
  try {
    const url =
      `https://api.mexc.com/api/v3/klines` +
      `?symbol=HBARUSDT&interval=${interval}` +
      `&startTime=${startMs}&endTime=${endMs}&limit=${limit}`;
    const data = await fetchJson(url);
    if (!Array.isArray(data)) return [];
    return data.map((c: any[]) => ({
      openTimeMs: Number(c[0]),
      closePrice: Number(c[4]),
    }));
  } catch (err: any) {
    console.warn(`MEXC fetch error: ${err.message}`);
    return [];
  }
}

export async function fetchAvgUsdConversion(
  client: PoolClient,
  period: string,
  startTimestamp: string,
  endTimestamp: string,
): Promise<void> {
  const intervals = getExchangeIntervals(period);
  const limitCandles = 100;

  // Convert nanosecond timestamps to milliseconds
  const origStartMs = Math.floor(Number(BigInt(startTimestamp) / 1_000_000n));
  const origEndMs = Math.floor(Number(BigInt(endTimestamp) / 1_000_000n));
  const periodMs = getPeriodMs(period);

  const newStartMs = Math.max(
    origStartMs,
    origEndMs - periodMs * limitCandles,
  );

  // Fetch from all 4 exchanges in parallel
  const [binance, okx, bitget, mexc] = await Promise.all([
    fetchBinance(intervals.binance, newStartMs, origEndMs, limitCandles),
    fetchOkx(intervals.okx, newStartMs, origEndMs, limitCandles),
    fetchBitget(intervals.bitget, newStartMs, origEndMs, limitCandles),
    fetchMexc(intervals.mexc, newStartMs, origEndMs, limitCandles),
  ]);

  const allData = [...binance, ...okx, ...bitget, ...mexc];
  if (allData.length === 0) {
    console.warn('avg_usd_conversion: no data from any exchange');
    return;
  }

  // Use temp table + SQL grouping to match the original implementation exactly
  await client.query('BEGIN');
  try {
    await client.query(`
      CREATE TEMP TABLE temp_price_data (
        open_time_ms bigint,
        close_price numeric
      ) ON COMMIT DROP
    `);

    // Batch insert using unnest
    const openTimes = allData.map((d) => String(d.openTimeMs));
    const closePrices = allData.map((d) => String(d.closePrice));
    await client.query(
      `INSERT INTO temp_price_data (open_time_ms, close_price)
       SELECT * FROM unnest($1::bigint[], $2::numeric[])`,
      [openTimes, closePrices],
    );

    // Group by period, average prices, build int8range, upsert
    await client.query(
      `WITH grouped AS (
         SELECT
           date_trunc($1, to_timestamp(open_time_ms / 1000.0)) AS truncated_ts,
           avg(close_price * 1e5)::bigint AS avg_close
         FROM temp_price_data
         GROUP BY 1
         ORDER BY 1
       ),
       final_output AS (
         SELECT
           int8range(
             truncated_ts::timestamp9::bigint,
             (lead(truncated_ts) OVER (ORDER BY truncated_ts))::timestamp9::bigint
           ) AS timestamp_range,
           avg_close AS total
         FROM grouped
       )
       INSERT INTO ecosystem.metric (name, period, timestamp_range, total)
       SELECT 'avg_usd_conversion', $1, timestamp_range, total
       FROM final_output
       WHERE upper(timestamp_range) IS NOT NULL
       ON CONFLICT (name, period, timestamp_range) DO UPDATE SET total = EXCLUDED.total`,
      [period],
    );

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  }
}
