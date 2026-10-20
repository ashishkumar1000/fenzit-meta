-- Permissions and realtime policy that pg_dump does not carry over to a fresh Supabase project.
-- Run AFTER schema.sql, data.sql and cron-jobs.sql. Copied from the live Fenzit-Be project (2026-10-20).

-- 1. Public functions: only the database owner and the backend's service role may run them.
--    Nobody on the public API (anon / signed-in users) can call them directly.
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to postgres, service_role;
-- New functions created later get the same lock-down by default.
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated, public;

-- 2. Eleven tables that only the backend (service role) may touch.
revoke all on table
  public.attendance_attempts, public.attendance_corrections, public.attendance_day_overrides,
  public.attendance_enrolments, public.attendance_office_assignments, public.attendance_onboarding,
  public.attendance_records, public.early_access_signups, public.leave_events,
  public.leave_request_days, public.leave_requests
from anon, authenticated;

-- 3. users: signed-in people may read, insert and delete through the API (policies still apply),
--    but may only UPDATE the name column, never role, tenant or anything else.
revoke update, references, trigger on table public.users from anon, authenticated;
grant update (name) on table public.users to authenticated;

-- 4. The attendance access view is read-only and backend-only.
revoke all on table public.attendance_access_state from anon, authenticated, service_role;
grant select on table public.attendance_access_state to service_role;

-- 5. Realtime: a signed-in user may only listen to their own notifications topic.
drop policy if exists notifications_topic_recipient_only on realtime.messages;
create policy notifications_topic_recipient_only on realtime.messages
  for select to public
  using (
    (realtime.topic() like 'user:%:notifications')
    and (split_part(realtime.topic(), ':', 2) = (auth.jwt() ->> 'sub'))
  );
