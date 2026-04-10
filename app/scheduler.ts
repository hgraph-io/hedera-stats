import * as cron from 'node-cron';
import { Pool } from 'pg';
import { jobs } from './registry';
import { runJob } from './runner';

const activeTasks: cron.ScheduledTask[] = [];

export function startScheduler(pool: Pool): void {
  console.log(`Starting scheduler with ${jobs.length} jobs...`);

  for (const job of jobs) {
    const task = cron.schedule(job.cron, async () => {
      try {
        await runJob(pool, job);
      } catch (err: any) {
        console.error(`[${job.name}] Unhandled error: ${err.message}`);
      }
    });

    activeTasks.push(task);
    console.log(`  Scheduled: ${job.name} (${job.cron}) - ${job.metrics.length} metrics [${job.period}]`);
  }

  console.log('Scheduler started');
}

export function stopScheduler(): void {
  for (const task of activeTasks) {
    task.stop();
  }
  activeTasks.length = 0;
  console.log('Scheduler stopped');
}
