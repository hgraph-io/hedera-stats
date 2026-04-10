import { statsPool, closePool } from './db';
import { setup } from './setup';
import { startScheduler, stopScheduler } from './scheduler';
import { runJob } from './runner';
import { jobs } from './registry';

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const isInit = args.includes('--init');
  const runOnce = args.find((a) => a.startsWith('--run='));

  console.log('Hedera Stats - Standalone Application');
  console.log('======================================');

  // Run database setup
  await setup(statsPool);

  if (isInit) {
    // Run all jobs once for initialization/backfill
    console.log('\nRunning initialization (all jobs)...');
    for (const job of jobs) {
      await runJob(statsPool, job);
    }
    console.log('Initialization complete');
    await closePool();
    return;
  }

  if (runOnce) {
    // Run a specific job once
    const jobName = runOnce.split('=')[1];
    const job = jobs.find((j) => j.name === jobName);
    if (!job) {
      console.error(`Unknown job: ${jobName}. Available: ${jobs.map((j) => j.name).join(', ')}`);
      await closePool();
      process.exit(1);
    }
    console.log(`\nRunning job: ${jobName}...`);
    await runJob(statsPool, job);
    await closePool();
    return;
  }

  // Start scheduler for continuous operation
  startScheduler(statsPool);

  // Graceful shutdown
  const shutdown = async (signal: string) => {
    console.log(`\n${signal} received, shutting down...`);
    stopScheduler();
    await closePool();
    process.exit(0);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  console.log('\nApp running. Waiting for scheduled jobs...');
  console.log('Press Ctrl+C to stop.\n');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
