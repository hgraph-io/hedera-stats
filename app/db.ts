import { Pool } from 'pg';
import { config } from './config';

export const statsPool = new Pool({
  host: config.statsDb.host,
  port: config.statsDb.port,
  database: config.statsDb.database,
  user: config.statsDb.user,
  password: config.statsDb.password,
  max: 10,
});

export async function closePool(): Promise<void> {
  await statsPool.end();
}
