-- Scheduled jobs (pg_cron). Not part of the pg_dump output, so exported separately.
-- Run on the target project after schema.sql, once pg_cron is enabled.
select cron.schedule('idempotency-log-cleanup', '0 * * * *', 'DELETE FROM idempotency_log WHERE created_at < now() - interval ''24 hours''');
select cron.schedule('attachment-uploads-cleanup', '0 3 * * *', 'DELETE FROM attachment_uploads WHERE expires_at < now() - interval ''1 day''');
select cron.schedule('notifications-cleanup', '10 * * * *', 'DELETE FROM notifications WHERE created_at < now() - interval ''30 days'' AND (pushed_at IS NOT NULL OR created_at < now() - interval ''90 days'')');
select cron.schedule('cron-job-run-details-cleanup', '0 3 * * *', 'delete from cron.job_run_details
     where start_time < now() - interval ''7 days''');
select cron.schedule('attendance-attempts-coordinate-cleanup', '10 3 * * *', 'update public.attendance_attempts
      set latitude = null, longitude = null, accuracy_m = null
    where outcome <> ''ok''
      and latitude is not null
      and attempted_at < now() - interval ''90 days''');
select cron.schedule('attendance-run-reminders', '*/5 * * * *', 'select public.attendance_run_reminders()');
