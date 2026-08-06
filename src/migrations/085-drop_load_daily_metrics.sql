-- 085-drop_load_daily_metrics.sql — drops the pre-rename ecosystem.load_daily_metrics()
-- procedure, superseded by ecosystem.load_metrics_day(). Its metrics array had been
-- emptied out, so every call failed with "cannot determine type of empty array";
-- the corresponding pg_cron job on the publisher has been unscheduled.

BEGIN;

DROP PROCEDURE IF EXISTS ecosystem.load_daily_metrics();

COMMIT;
