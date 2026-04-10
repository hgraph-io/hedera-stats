import * as fs from 'fs';
import * as path from 'path';
import { PoolClient } from 'pg';

// Files that use pg_http and are reimplemented in TypeScript
const API_METRIC_FILES = new Set([
  'avg_usd_conversion.sql',
]);

// Files that are raw INSERT statements, not CREATE FUNCTION
const STATIC_DATA_FILES = new Set([
  'hbar_total_supply.sql',
]);

const SKIP_DIRS = new Set(['legacy', 'setup']);

function findSqlFiles(dir: string): string[] {
  const results: string[] = [];
  if (!fs.existsSync(dir)) return results;

  for (const entry of fs.readdirSync(dir)) {
    const full = path.join(dir, entry);
    if (fs.statSync(full).isDirectory()) {
      if (SKIP_DIRS.has(entry)) continue;
      results.push(...findSqlFiles(full));
    } else if (entry.endsWith('.sql')) {
      results.push(full);
    }
  }
  return results;
}

function transformSql(sql: string): string {
  // Replace custom enum types not available on the stats DB
  return sql.replace(/public\.interval_granularity/g, 'text');
}

export async function loadMetricFunctions(
  client: PoolClient,
  metricsDir: string,
): Promise<void> {
  const sqlFiles = findSqlFiles(metricsDir);
  let loaded = 0;
  let skipped = 0;

  for (const file of sqlFiles) {
    const filename = path.basename(file);

    if (API_METRIC_FILES.has(filename) || STATIC_DATA_FILES.has(filename)) {
      skipped++;
      continue;
    }

    const sql = fs.readFileSync(file, 'utf-8');
    const transformed = transformSql(sql);

    try {
      await client.query(transformed);
      loaded++;
    } catch (err: any) {
      console.error(
        `Failed to load ${path.relative(metricsDir, file)}: ${err.message}`,
      );
    }
  }

  console.log(`Loaded ${loaded} metric functions (${skipped} skipped)`);
}

export async function loadMetricDescriptions(
  client: PoolClient,
  filePath: string,
): Promise<void> {
  if (!fs.existsSync(filePath)) {
    console.warn('metric_descriptions.sql not found, skipping');
    return;
  }

  const sql = fs.readFileSync(filePath, 'utf-8');
  try {
    await client.query(sql);
    console.log('Loaded metric descriptions');
  } catch (err: any) {
    console.error(`Failed to load metric descriptions: ${err.message}`);
  }
}

export async function loadHbarTotalSupply(
  client: PoolClient,
  filePath: string,
): Promise<void> {
  if (!fs.existsSync(filePath)) {
    console.warn('hbar_total_supply.sql not found, skipping');
    return;
  }

  const sql = fs.readFileSync(filePath, 'utf-8');
  try {
    await client.query(sql);
    console.log('Loaded hbar_total_supply data');
  } catch (err: any) {
    console.error(`Failed to load hbar_total_supply: ${err.message}`);
  }
}
