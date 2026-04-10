import { Pool } from 'pg';
import * as path from 'path';
import { config } from './config';
import {
  loadMetricFunctions,
  loadMetricDescriptions,
  loadHbarTotalSupply,
} from './sql-loader';

function esc(str: string): string {
  return str.replace(/'/g, "''");
}

export async function setup(pool: Pool): Promise<void> {
  const client = await pool.connect();
  try {
    console.log('Setting up database...');

    // Extensions
    await client.query('CREATE EXTENSION IF NOT EXISTS timestamp9');
    await client.query('CREATE EXTENSION IF NOT EXISTS postgres_fdw');

    // Schema
    await client.query('CREATE SCHEMA IF NOT EXISTS ecosystem');

    // Types
    await client.query(`
      DO $$ BEGIN
        CREATE TYPE ecosystem.metric_total AS (int8range int8range, total bigint);
      EXCEPTION WHEN duplicate_object THEN NULL;
      END $$
    `);

    // Tables
    await client.query(`
      CREATE TABLE IF NOT EXISTS ecosystem.metric (
        name text,
        period text,
        timestamp_range int8range,
        total bigint,
        UNIQUE (name, period, timestamp_range)
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS ecosystem.metric_description (
        name text PRIMARY KEY,
        description text,
        methodology text
      )
    `);

    // Foreign Data Wrapper for mirror node
    const mn = config.mirrorNode;
    if (mn.host) {
      console.log(
        `Setting up FDW to mirror node at ${mn.host}:${mn.port}/${mn.database}...`,
      );

      // Recreate server (CASCADE drops dependent foreign tables)
      await client.query('DROP SERVER IF EXISTS mirror_node CASCADE');

      await client.query(`
        CREATE SERVER mirror_node
        FOREIGN DATA WRAPPER postgres_fdw
        OPTIONS (
          host '${esc(mn.host)}',
          port '${mn.port}',
          dbname '${esc(mn.database)}',
          fetch_size '50000'
        )
      `);

      await client.query(`
        CREATE USER MAPPING FOR CURRENT_USER
        SERVER mirror_node
        OPTIONS (
          user '${esc(mn.user)}',
          password '${esc(mn.password)}'
        )
      `);

      // Import mirror node tables into public schema
      try {
        await client.query(`
          IMPORT FOREIGN SCHEMA public
          FROM SERVER mirror_node INTO public
        `);
        console.log('Imported mirror node public schema');
      } catch (err: any) {
        console.warn(
          'Could not import full public schema:',
          err.message,
        );
        console.log('Attempting individual table imports...');
        const tables = [
          'entity',
          'transaction',
          'crypto_transfer',
          'contract_result',
          'contract_log',
          'token',
          'nft_transfer',
        ];
        for (const table of tables) {
          try {
            await client.query(`
              IMPORT FOREIGN SCHEMA public LIMIT TO ("${table}")
              FROM SERVER mirror_node INTO public
            `);
            console.log(`  Imported: ${table}`);
          } catch {
            console.warn(`  Skipped: ${table}`);
          }
        }
      }

      // Try importing erc schema if it exists on the mirror node
      try {
        await client.query(
          'CREATE SCHEMA IF NOT EXISTS erc',
        );
        await client.query(`
          IMPORT FOREIGN SCHEMA erc
          FROM SERVER mirror_node INTO erc
        `);
        console.log('Imported mirror node erc schema');
      } catch {
        console.log('No erc schema on mirror node (ok)');
      }
    } else {
      console.warn(
        'No MIRROR_NODE_HOST configured - skipping FDW setup. SQL metrics will not work.',
      );
    }

    // Set search path for this session
    await client.query('SET search_path TO ecosystem, public');

    // Load metric functions from SQL files
    const sqlDir = path.resolve(__dirname, '..', 'src', 'metrics');
    await loadMetricFunctions(client, sqlDir);

    // Load metric descriptions
    const descFile = path.resolve(
      __dirname,
      '..',
      'src',
      'metric_descriptions.sql',
    );
    await loadMetricDescriptions(client, descFile);

    // Load hbar_total_supply static data
    const supplyFile = path.resolve(
      __dirname,
      '..',
      'src',
      'metrics',
      'hbar-defi',
      'hbar_total_supply.sql',
    );
    await loadHbarTotalSupply(client, supplyFile);

    console.log('Database setup complete');
  } finally {
    client.release();
  }
}
