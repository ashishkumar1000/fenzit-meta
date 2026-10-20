


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "btree_gist" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";





SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."jobs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "job_number" "text" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "technician_id" "uuid" NOT NULL,
    "service_location" "text" NOT NULL,
    "scheduled_start" timestamp with time zone NOT NULL,
    "scheduled_end" timestamp with time zone,
    "status" "text" DEFAULT 'scheduled'::"text" NOT NULL,
    "current_step" "text",
    "priority" "text" DEFAULT 'normal'::"text" NOT NULL,
    "description" "text",
    "notes_for_technician" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "skill_id" "uuid" NOT NULL,
    "workflow_template_id" "uuid" NOT NULL,
    "workflow_template_version" integer NOT NULL,
    CONSTRAINT "jobs_priority_check" CHECK (("priority" = ANY (ARRAY['normal'::"text", 'urgent'::"text"]))),
    CONSTRAINT "jobs_status_check" CHECK (("status" = ANY (ARRAY['scheduled'::"text", 'in_progress'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."jobs" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."advance_workflow_step"("p_job_id" "uuid", "p_tenant_id" "uuid", "p_actor_id" "uuid", "p_step" "text", "p_new_status" "text", "p_expected_current_step" "text", "p_latitude" double precision DEFAULT NULL::double precision, "p_longitude" double precision DEFAULT NULL::double precision, "p_accuracy" double precision DEFAULT NULL::double precision, "p_location_captured" boolean DEFAULT NULL::boolean, "p_reason" "text" DEFAULT NULL::"text", "p_accuracy_flagged" boolean DEFAULT NULL::boolean) RETURNS SETOF "public"."jobs"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_job jobs%ROWTYPE;
BEGIN
  -- Tenant-scoped row lock. A missing/cross-tenant row returns the empty set,
  -- which the app maps to 404 (cross-tenant is indistinguishable from not-found).
  SELECT * INTO v_job
  FROM jobs
  WHERE id = p_job_id AND tenant_id = p_tenant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- A finished/cancelled job cannot advance. Custom SQLSTATE the app maps to
  -- 409 JOB_NOT_MODIFIABLE (PTxxx convention: last 3 digits = HTTP status; the
  -- app reads error.code directly).
  IF v_job.status NOT IN ('scheduled', 'in_progress') THEN
    RAISE EXCEPTION 'job % not advanceable in status %', p_job_id, v_job.status
      USING ERRCODE = 'PT409';
  END IF;

  -- Compare-and-set: if current_step moved between the service's read and now
  -- (a concurrent advance / offline replay), reject the stale write. IS DISTINCT
  -- FROM is null-safe (the first on_my_way advance expects current_step = NULL).
  IF v_job.current_step IS DISTINCT FROM p_expected_current_step THEN
    RAISE EXCEPTION 'workflow step changed concurrently (expected %, found %)',
      p_expected_current_step, v_job.current_step
      USING ERRCODE = 'PT409';
  END IF;

  -- p_new_status is 'in_progress' for on_my_way, 'completed' for completed,
  -- else NULL (COALESCE leaves status unchanged at in_progress).
  UPDATE jobs
  SET current_step = p_step,
      status       = COALESCE(p_new_status, status),
      completed_at = CASE WHEN p_new_status = 'completed' THEN now() ELSE completed_at END,
      updated_at   = now()
  WHERE id = p_job_id;

  -- Every step appends an immutable activity-log entry (FR-11). tenant_id and
  -- actor_id are NOT NULL on activity_logs, so both must be supplied.
  -- Merge location data into metadata: lat/long must arrive together or not at all.
  INSERT INTO activity_logs (job_id, tenant_id, event_type, actor_id, metadata)
  VALUES (
    p_job_id, p_tenant_id, 'step_' || p_step, p_actor_id,
    CASE
      WHEN p_latitude IS NOT NULL AND p_longitude IS NOT NULL THEN
        jsonb_strip_nulls(jsonb_build_object(
          'latitude', p_latitude,
          'longitude', p_longitude,
          'accuracy', p_accuracy,
          'locationCaptured', p_location_captured,
          'reason', p_reason,
          'accuracyFlagged', p_accuracy_flagged
        ))
      WHEN p_location_captured IS NOT NULL THEN
        jsonb_strip_nulls(jsonb_build_object(
          'locationCaptured', p_location_captured,
          'reason', p_reason
        ))
      ELSE NULL
    END
  );

  -- Notify the tenant owner (Story 3.1). Self-notification guard: an owner
  -- advancing their own job must not notify themselves.
  INSERT INTO notifications (tenant_id, user_id, job_id, event_type, payload)
  SELECT p_tenant_id,
         t.owner_id,
         p_job_id,
         p_step,
         jsonb_build_object(
           'job_number', v_job.job_number,
           'step', p_step,
           'technician_name', COALESCE(NULLIF(u.name, ''), 'A technician')
         )
  FROM tenants t
  LEFT JOIN users u ON u.id = p_actor_id
  WHERE t.id = p_tenant_id
    AND t.owner_id <> p_actor_id;

  RETURN QUERY SELECT * FROM jobs WHERE id = p_job_id AND tenant_id = p_tenant_id;
END $$;


ALTER FUNCTION "public"."advance_workflow_step"("p_job_id" "uuid", "p_tenant_id" "uuid", "p_actor_id" "uuid", "p_step" "text", "p_new_status" "text", "p_expected_current_step" "text", "p_latitude" double precision, "p_longitude" double precision, "p_accuracy" double precision, "p_location_captured" boolean, "p_reason" "text", "p_accuracy_flagged" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_add_holiday"("p_tenant_id" "uuid", "p_holiday_date" "date", "p_name" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_today      date;
  v_holiday_id uuid;
begin
  perform public.attendance_lock_tenant(p_tenant_id, true);

  v_today := public.attendance_today(p_tenant_id);

  begin
    insert into public.holidays (tenant_id, holiday_date, name)
      values (p_tenant_id, p_holiday_date, p_name)
      returning id into v_holiday_id;
  exception
    when unique_violation then
      raise exception 'a holiday on % already exists in tenant %', p_holiday_date, p_tenant_id
        using errcode = 'PT409',
              hint = 'ATTENDANCE_HOLIDAY_TAKEN';
  end;

  -- Future dates broadcast to tracked employees (AD-13); past dates are
  -- silent. Gated on setup COMPLETED and the module still enabled — the
  -- kill switch is the module's off act (FR-1): no fan-out while off.
  if p_holiday_date > v_today then
    if exists (
      select 1 from public.attendance_settings
      where tenant_id = p_tenant_id
        and setup_completed_at is not null
        and enabled
    ) then
      insert into public.notifications
        (tenant_id, user_id, job_id, event_type, payload,
         entity_type, entity_id, dedupe_key)
      select p_tenant_id,
             e.employee_id,
             null,
             'attendance.holiday_added',
             jsonb_build_object(
               'holidayName', p_name,
               'holidayDate', to_char(p_holiday_date, 'YYYY-MM-DD')
             ),
             'attendance',
             v_holiday_id,
             p_tenant_id::text || ':attendance.holiday_added:'
               || e.employee_id::text || ':' || v_holiday_id::text
      from public.attendance_enrolments e
      join public.users u on u.id = e.employee_id
      join public.attendance_office_assignments a
        on a.employee_id = e.employee_id
       and a.valid @> p_holiday_date
      join public.attendance_offices o
        on o.id = a.office_id and o.archived_at is null
      where u.tenant_id = p_tenant_id
        and e.valid @> p_holiday_date;
    end if;
  end if;

  return v_holiday_id;
end;
$$;


ALTER FUNCTION "public"."attendance_add_holiday"("p_tenant_id" "uuid", "p_holiday_date" "date", "p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_archive_office"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_office_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  perform public.attendance_lock_tenant(p_tenant_id, true);

  if not exists (
    select 1 from public.attendance_offices
    where id = p_office_id
      and tenant_id = p_tenant_id
  ) then
    raise exception 'office % not found in tenant %', p_office_id, p_tenant_id
      using errcode = 'PT404',
            hint = 'ATTENDANCE_OFFICE_NOT_FOUND';
  end if;

  -- Already archived → idempotent no-op success (a double-tap or a retry
  -- must not error, and must not re-stamp archived_at).
  if exists (
    select 1 from public.attendance_offices
    where id = p_office_id
      and archived_at is not null
  ) then
    return;
  end if;

  -- The shared blocker predicate (above) — single source, no copy-paste.
  if exists (
    select 1
    from public.attendance_office_archive_blockers(p_tenant_id, p_office_id)
  ) then
    raise exception 'office % has tracked employees assigned', p_office_id
      using errcode = 'PT409',
            hint = 'ATTENDANCE_OFFICE_ARCHIVE_BLOCKED';
  end if;

  update public.attendance_offices
    set archived_at = now()
    where id = p_office_id;
end;
$$;


ALTER FUNCTION "public"."attendance_archive_office"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_office_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_complete_setup"("p_tenant_id" "uuid", "p_actor_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_today date;
  v_offending_office_name text;
begin
  -- Tenant-wide RPC: exclusive tenant lock first (AD-5). No employee rows
  -- are changed here, so no employee locks.
  perform public.attendance_lock_tenant(p_tenant_id, true);

  -- Setup must have started and not already be completed.
  if not exists (
    select 1 from public.attendance_settings
    where tenant_id = p_tenant_id and setup_completed_at is null
  ) then
    raise exception 'attendance setup for tenant % not in progress', p_tenant_id
      using errcode = 'PT409',
            hint = 'ATTENDANCE_SETUP_ALREADY_COMPLETED';
  end if;

  v_today := public.attendance_today(p_tenant_id);

  -- Gate 1: at least one active office.
  -- D3 (user decision 2026-09-29): the message tells the owner WHY the
  -- completion failed and WHAT to do next; the tenant-id plumbing moves
  -- to `detail` so support logs still correlate the rejection.
  if not exists (
    select 1 from public.attendance_offices o
    where o.tenant_id = p_tenant_id
      and o.archived_at is null
  ) then
    raise exception 'attendance setup could not be completed: no office has been added yet. Add an office, then try again.'
      using errcode = 'PT422',
            hint = 'ATTENDANCE_SETUP_INCOMPLETE',
            detail = format('tenant %s has no active office', p_tenant_id);
  end if;

  -- Gate 2: at least one tracked employee whose live office assignment
  -- covers today (the 15-7 reconciliation: enrolment covers the date AND
  -- the covering assignment's office is not archived).
  if not exists (
    select 1
    from public.attendance_enrolments e
    join public.attendance_office_assignments a on a.employee_id = e.employee_id
    join public.attendance_offices o on o.id = a.office_id
    join public.users u on u.id = e.employee_id
    where u.tenant_id = p_tenant_id
      and e.valid @> v_today
      and a.valid @> v_today
      and o.archived_at is null
  ) then
    raise exception 'attendance setup could not be completed: no employee is enrolled for today with a live office assignment. Enrol an employee and assign them to an office, then try again.'
      using errcode = 'PT422',
            hint = 'ATTENDANCE_SETUP_INCOMPLETE',
            detail = format('tenant %s has no tracked employee with an office assignment', p_tenant_id);
  end if;

  -- Gate 3 (18-5): every active office must carry a rule covering today —
  -- an owner-facing timing rule for FR-7's thresholds must exist at the
  -- moment tracking turns on, whatever the client did (the wizard's own
  -- liveOfficesMissingRule===0 gate is FE-side; this is the DB guard).
  -- D3 (user decision 2026-09-29): the rejection names the FIRST
  -- offending office so the owner knows where to act; the earlier
  -- `exists` probe is replaced by this named pick (one scan, no double
  -- query, and the message stays exact for the FE's hint-mapped error).
  select coalesce(nullif(o.name, ''), '(unnamed office)')
    into v_offending_office_name
    from public.attendance_offices o
    where o.tenant_id = p_tenant_id
      and o.archived_at is null
      and not exists (
        select 1
        from public.attendance_office_rules r
        where r.office_id = o.id
          and r.valid @> v_today
      )
    limit 1;

  if v_offending_office_name is not null then
    raise exception 'attendance setup could not be completed: office «%» has no timing rule covering today. Add a rule for this office, then try again.', v_offending_office_name
      using errcode = 'PT422',
            hint = 'ATTENDANCE_SETUP_INCOMPLETE',
            detail = format('tenant %s has an active office without a rule', p_tenant_id);
  end if;

  -- Completing setup turns the module on (PRD: the wizard IS the enable
  -- act); enabled=false remains the kill switch from then on.
  update public.attendance_settings
    set setup_completed_at = now(),
        enabled = true
    where tenant_id = p_tenant_id;
end;
$$;


ALTER FUNCTION "public"."attendance_complete_setup"("p_tenant_id" "uuid", "p_actor_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_create_office"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_name" "text", "p_latitude" double precision, "p_longitude" double precision, "p_radius_m" integer, "p_start_time" time without time zone, "p_end_time" time without time zone, "p_late_cutoff_minutes" integer, "p_full_day_hours" numeric, "p_half_day_hours" numeric) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_office_id uuid;
  v_today     date;
begin
  v_today := public.attendance_today(p_tenant_id);

  insert into public.attendance_offices (tenant_id, name, latitude, longitude, radius_m)
    values (p_tenant_id, p_name, p_latitude, p_longitude, p_radius_m)
    returning id into v_office_id;

  insert into public.attendance_office_rules
    (office_id, tenant_id, valid, start_time, end_time,
     late_cutoff_minutes, full_day_hours, half_day_hours)
    values (
      v_office_id,
      p_tenant_id,
      daterange(v_today, null, '[)'),
      p_start_time,
      p_end_time,
      p_late_cutoff_minutes,
      p_full_day_hours,
      p_half_day_hours
    );

  return v_office_id;
exception
  when unique_violation then
    raise exception 'an office named % already exists in tenant %', p_name, p_tenant_id
      using errcode = 'PT409',
            hint = 'ATTENDANCE_OFFICE_NAME_TAKEN';
end;
$$;


ALTER FUNCTION "public"."attendance_create_office"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_name" "text", "p_latitude" double precision, "p_longitude" double precision, "p_radius_m" integer, "p_start_time" time without time zone, "p_end_time" time without time zone, "p_late_cutoff_minutes" integer, "p_full_day_hours" numeric, "p_half_day_hours" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_enrolment_coverage_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_employee_id uuid;
  v_open_end constant date := date '9999-12-31';
begin
  v_employee_id := coalesce(new.employee_id, old.employee_id);

  -- No assignment may reach outside an enrolment (any office state).
  if exists (
    select 1
    from public.attendance_office_assignments a
    where a.employee_id = v_employee_id
      and not exists (
        select 1
        from public.attendance_enrolments e
        where e.employee_id = a.employee_id
          and e.valid @> a.valid
      )
  ) then
    raise exception
      'employee % has an office assignment outside any enrolment',
      v_employee_id
      using errcode = '23514',
            hint = 'ATTENDANCE_ASSIGNMENT_GAP';
  end if;

  -- Coverage = exact endpoint chaining (any office state — archived offices
  -- still cover the past they once served, FR-5): the first leg starts at
  -- the period start, every next leg starts where the previous ended, and
  -- the chain reaches the period's end (sentinel for open ranges).
  if exists (
    select 1
    from public.attendance_enrolments e
    cross join lateral (
      with legs as (
        select lower(a.valid) as s,
               coalesce(upper(a.valid), v_open_end) as t,
               lag(coalesce(upper(a.valid), v_open_end)) over (order by lower(a.valid)) as prev_t
        from public.attendance_office_assignments a
        where a.employee_id = e.employee_id
          and a.valid <@ e.valid
      )
      select (select min(s) from legs) is distinct from lower(e.valid) as gap_start,
             coalesce((select bool_or(prev_t is not null and prev_t <> s) from legs), false) as gap_mid,
             (select max(t) from legs) is distinct from coalesce(upper(e.valid), v_open_end) as gap_end
    ) g
    where e.employee_id = v_employee_id
      and (g.gap_start or g.gap_mid or g.gap_end)
  ) then
    raise exception
      'employee % has an enrolled date without an office assignment',
      v_employee_id
      using errcode = '23514',
            hint = 'ATTENDANCE_ASSIGNMENT_GAP';
  end if;

  -- CURRENT-OR-FUTURE periods must be chained over LIVE assignments — an
  -- archived office can never serve a check-in. Closed history is exempt:
  -- after office A is archived, the employee can still be disabled,
  -- reassigned and re-enabled.
  if exists (
    select 1
    from public.attendance_enrolments e
    join public.users u on u.id = e.employee_id
    cross join lateral (
      with legs as (
        select lower(a.valid) as s,
               coalesce(upper(a.valid), v_open_end) as t,
               lag(coalesce(upper(a.valid), v_open_end)) over (order by lower(a.valid)) as prev_t
        from public.attendance_office_assignments a
        join public.attendance_offices o on o.id = a.office_id
        where a.employee_id = e.employee_id
          and o.archived_at is null
          and a.valid <@ e.valid
      )
      select (select min(s) from legs) is distinct from lower(e.valid) as gap_start,
             coalesce((select bool_or(prev_t is not null and prev_t <> s) from legs), false) as gap_mid,
             (select max(t) from legs) is distinct from coalesce(upper(e.valid), v_open_end) as gap_end
    ) g
    where e.employee_id = v_employee_id
      and coalesce(upper(e.valid), v_open_end) > public.attendance_today(u.tenant_id)
      and (g.gap_start or g.gap_mid or g.gap_end)
  ) then
    raise exception
      'employee % has a current or future enrolled date without a live office assignment',
      v_employee_id
      using errcode = '23514',
            hint = 'ATTENDANCE_ASSIGNMENT_GAP';
  end if;

  return null;
end;
$$;


ALTER FUNCTION "public"."attendance_enrolment_coverage_guard"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_holiday_impact"("p_tenant_id" "uuid", "p_date" "date") RETURNS TABLE("employee_id" "uuid", "employee_name" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  perform public.attendance_today(p_tenant_id);

  return query
    select e.employee_id,
           coalesce(
             nullif(u.name, ''),
             u.country_code || u.phone_number,
             'Unknown employee'
           ) as employee_name
    from public.attendance_enrolments e
    join public.users u on u.id = e.employee_id
    join public.attendance_office_assignments a
      on a.employee_id = e.employee_id
     and a.valid @> p_date
    join public.attendance_offices o
      on o.id = a.office_id and o.archived_at is null
    where u.tenant_id = p_tenant_id
      and e.valid @> p_date;
end;
$$;


ALTER FUNCTION "public"."attendance_holiday_impact"("p_tenant_id" "uuid", "p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_lock_employee"("p_employee_id" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select pg_advisory_xact_lock(hashtextextended('employee:' || p_employee_id::text, 0));
$$;


ALTER FUNCTION "public"."attendance_lock_employee"("p_employee_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_lock_tenant"("p_tenant_id" "uuid", "p_exclusive" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if p_exclusive is true then
    perform pg_advisory_xact_lock(hashtextextended('tenant:' || p_tenant_id::text, 0));
  elsif p_exclusive is false then
    perform pg_advisory_xact_lock_shared(hashtextextended('tenant:' || p_tenant_id::text, 0));
  else
    raise exception 'p_exclusive must be true or false'
      using errcode = 'PT400',
            hint = 'VALIDATION_ERROR';
  end if;
end;
$$;


ALTER FUNCTION "public"."attendance_lock_tenant"("p_tenant_id" "uuid", "p_exclusive" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_office_archive_blockers"("p_tenant_id" "uuid", "p_office_id" "uuid") RETURNS TABLE("employee_id" "uuid", "employee_name" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_today date;
begin
  v_today := public.attendance_today(p_tenant_id);

  return query
    select distinct a.employee_id,
           coalesce(
             nullif(u.name, ''),
             u.country_code || u.phone_number,
             'Unknown employee'
           ) as employee_name
    from public.attendance_office_assignments a
    join public.users u on u.id = a.employee_id
    where a.office_id = p_office_id
      and u.tenant_id = p_tenant_id
      and coalesce(upper(a.valid), 'infinity'::date) > v_today
      and exists (
        select 1
        from public.attendance_enrolments e
        where e.employee_id = a.employee_id
          and e.valid @> lower(a.valid)
      )
    order by 2;
end;
$$;


ALTER FUNCTION "public"."attendance_office_archive_blockers"("p_tenant_id" "uuid", "p_office_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_remove_holiday"("p_tenant_id" "uuid", "p_holiday_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_today        date;
  v_holiday_date date;
  v_holiday_name text;
begin
  perform public.attendance_lock_tenant(p_tenant_id, true);

  v_today := public.attendance_today(p_tenant_id);

  select holiday_date, name into v_holiday_date, v_holiday_name
  from public.holidays
  where id = p_holiday_id
    and tenant_id = p_tenant_id;

  if v_holiday_date is null then
    raise exception 'holiday % not found in tenant %', p_holiday_id, p_tenant_id
      using errcode = 'PT404',
            hint = 'ATTENDANCE_HOLIDAY_NOT_FOUND';
  end if;

  delete from public.holidays
    where id = p_holiday_id
      and tenant_id = p_tenant_id;

  -- Same completed+enabled gate as add (kill-switch asymmetry finding).
  if v_holiday_date > v_today then
    if exists (
      select 1 from public.attendance_settings
      where tenant_id = p_tenant_id
        and setup_completed_at is not null
        and enabled
    ) then
      insert into public.notifications
        (tenant_id, user_id, job_id, event_type, payload,
         entity_type, entity_id, dedupe_key)
      select p_tenant_id,
             e.employee_id,
             null,
             'attendance.holiday_removed',
             jsonb_build_object(
               'holidayName', v_holiday_name,
               'holidayDate', to_char(v_holiday_date, 'YYYY-MM-DD')
             ),
             'attendance',
             p_holiday_id,
             p_tenant_id::text || ':attendance.holiday_removed:'
               || e.employee_id::text || ':' || p_holiday_id::text
      from public.attendance_enrolments e
      join public.users u on u.id = e.employee_id
      join public.attendance_office_assignments a
        on a.employee_id = e.employee_id
       and a.valid @> v_holiday_date
      join public.attendance_offices o
        on o.id = a.office_id and o.archived_at is null
      where u.tenant_id = p_tenant_id
        and e.valid @> v_holiday_date;
    end if;
  end if;
end;
$$;


ALTER FUNCTION "public"."attendance_remove_holiday"("p_tenant_id" "uuid", "p_holiday_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_remove_weekly_off_override"("p_tenant_id" "uuid", "p_employee_id" "uuid", "p_effective_from" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_today          date;
  v_effective_from date;
begin
  perform public.attendance_lock_tenant(p_tenant_id, true);

  v_today := public.attendance_today(p_tenant_id);
  v_effective_from := greatest(coalesce(p_effective_from, v_today), v_today);

  if not exists (
    select 1 from public.users
    where id = p_employee_id
      and tenant_id = p_tenant_id
  ) then
    raise exception 'employee % not found in tenant %', p_employee_id, p_tenant_id
      using errcode = 'PT404',
            hint = 'ATTENDANCE_EMPLOYEE_NOT_FOUND';
  end if;

  delete from public.attendance_weekly_off_overrides
    where employee_id = p_employee_id
      and lower(valid) >= v_effective_from;

  update public.attendance_weekly_off_overrides
    set valid = daterange(lower(valid), v_effective_from, '[)')
    where employee_id = p_employee_id
      and valid @> v_effective_from;
end;
$$;


ALTER FUNCTION "public"."attendance_remove_weekly_off_override"("p_tenant_id" "uuid", "p_employee_id" "uuid", "p_effective_from" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_run_reminders"("p_now" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant   record;
  v_tenant_id uuid;
  v_owner_id  uuid;
  v_tz        text;
  v_today     date;
  v_now_min   integer;  -- tenant wall-clock minute-of-day at tick time
  v_tick      timestamptz; -- coalesce(p_now, now()) — the injected clock
begin
  -- One pass per tenant with the module on (AD-25: enabled + completed
  -- setup); each tenant runs in its own BEGIN…EXCEPTION sub-block.
  for v_tenant in
    select t.id as tenant_id, t.owner_id, t.timezone
    from public.tenants t
    join public.attendance_settings s on s.tenant_id = t.id
    where s.enabled = true
      and s.setup_completed_at is not null
      and t.owner_id is not null
  loop
    begin
      v_tenant_id := v_tenant.tenant_id;
      v_owner_id  := v_tenant.owner_id;
      v_tz        := v_tenant.timezone;
      v_tick      := coalesce(p_now, now());
      v_today     := coalesce(
        (v_tick at time zone v_tz)::date,
        public.attendance_today(v_tenant_id)
      );
      -- floor(), not PG's rounding ::int cast: a tick in
      -- [threshold - 30s, threshold) must still read the PREVIOUS minute
      -- (bug-bash 2026-10-02 B-BUG-1 — 09:14:59 fired arms a minute early).
      v_now_min   := (floor(extract(epoch from (v_tick at time zone v_tz))
                          / 60))::int % 1440;

      -- ------------------------------------------------------------
      -- Pending-leave reminder: the owner, once per day at 10:00 tenant
      -- wall time (FR-23), when any pending leave day exists (a request's
      -- state lives on its per-day rows; count distinct requests). One
      -- insert per day per owner via the dedupe key — requests arriving
      -- after 10:00 stay silent until tomorrow (FR-23's "once a day").
      -- The (entity_type, entity_id) deep-link pair stays all-NULL
      -- (notifications_entity_pair_chk): the payload aggregates a count
      -- over MANY requests, so no single request is a deep-link target.
      -- ------------------------------------------------------------
      if v_now_min >= (extract(epoch from time '10:00') / 60)::int then
        insert into public.notifications
          (tenant_id, user_id, job_id, event_type, payload,
           entity_type, entity_id, dedupe_key)
        select
          v_tenant_id, v_owner_id, null::uuid,
          'leave.pending_reminder',
          jsonb_build_object('pendingCount', pend.pending_count),
          null::text, null::uuid,
          v_tenant_id || ':leave.pending_reminder:' || v_owner_id
            || ':' || v_today
        from (
          select count(distinct lrd.leave_request_id) as pending_count
          from public.leave_request_days lrd
          where lrd.tenant_id = v_tenant_id
            and lrd.state = 'pending'
        ) pend
        where pend.pending_count > 0
        on conflict (dedupe_key) where dedupe_key is not null do nothing;
      end if;

      -- ------------------------------------------------------------
      -- Employee + office-summary reminders over ONE shared fact CTE
      -- mirroring the TS day-context reads for today (AD-22 subset).
      -- No covering rule for the date → the employee drops out of facts
      -- entirely (AD-22: no rule → no thresholds to be late against).
      -- Enrolments dedupe to ONE row per employee — oldest valid period
      -- wins, the same pick as the TS read and the monthly roster's
      -- `distinct on`; without it a re-enrolment's overlapping rows
      -- MULTIPLY facts and arm 3's count(*) overstates the office
      -- summary (the audit's inflated-count finding). Arms 1/2 are
      -- unaffected in effect (the dedupe key swallows repeats), but one
      -- set of facts keeps every arm on the same input.
      -- ------------------------------------------------------------
      with facts as (
        select
          f.employee_id,
          f.office_id,
          f.office_name,
          f.start_min,
          f.end_min,
          f.cutoff,
          f.midpoint_min,
          f.is_working_day,
          f.full_day_leave,
          f.first_half_leave,
          f.second_half_leave,
          f.adjudicated,
          f.checkin_at,
          f.checkout_at,
          f.late_min,
          f.grace_skip
        from (
          select distinct on (inner_facts.employee_id)
            inner_facts.*
          from (
            select
              e.employee_id,
              a.office_id,
              o.name as office_name,
              (extract(epoch from r.start_time) / 60)::int as start_min,
              (extract(epoch from r.end_time)   / 60)::int as end_min,
              r.late_cutoff_minutes as cutoff,
              -- midpointMinute parity with DayContext: start + floor((end-start)/2)
              (extract(epoch from r.start_time) / 60)::int
                + (((extract(epoch from r.end_time) / 60)::int
                    - (extract(epoch from r.start_time) / 60)::int) / 2)
                as midpoint_min,
              -- Working day = not a tenant holiday today AND not the employee's
              -- effective weekly off today (the override REPLACES the tenant
              -- default when one covers the date — the pickWeeklyOffDays
              -- contract; days[] is ISO weekday 1=Mon..7=Sun, isodow matches).
              (not exists (
                 select 1 from public.holidays h
                 where h.tenant_id = v_tenant_id
                   and h.holiday_date = v_today
               )
               and not coalesce(
                 (select extract(isodow from v_today)::int = any (wov.days)
                  from public.attendance_weekly_off_overrides wov
                  where wov.employee_id = e.employee_id
                    and wov.valid @> v_today
                  limit 1),
                 (select extract(isodow from v_today)::int = any (wdef.days)
                  from public.attendance_weekly_off_defaults wdef
                  where wdef.tenant_id = v_tenant_id
                    and wdef.valid @> v_today
                  limit 1),
                 false)) as is_working_day,
              -- Active leave facts for today (at most one per day — the
              -- leave_request_days_active_uq partial unique index); the
              -- leave part rides the parent request (full_day | first_half |
              -- second_half). Only APPROVED shifts or suppresses (AD-14).
              -- IS TRUE (not a bare boolean): an employee with no leave day
              -- at all reads ld.state as NULL, and a NULL flag would make
              -- `not full_day_leave` NULL — silently dropping EVERY
              -- no-leave employee from the check-in/summary arms.
              ((ld.state = 'approved' and lr.part = 'full_day') is true)
                as full_day_leave,
              ((ld.state = 'approved' and lr.part = 'first_half') is true)
                as first_half_leave,
              ((ld.state = 'approved' and lr.part = 'second_half') is true)
                as second_half_leave,
              -- Rule 1 short-circuit: an active status-only override is an
              -- owner adjudication of this day.
              (ovd.id is not null and ovd.status is not null) as adjudicated,
              -- Effective instants: the override's manual instant REPLACES the
              -- record's (times-only overrides continue through the rules); an
              -- adjudicating status override contributes no instants.
              coalesce(ovd.manual_checkin_at, rec.checkin_at)  as checkin_at,
              coalesce(ovd.manual_checkout_at, rec.checkout_at) as checkout_at,
              -- floor() here too (same rounding class as v_now_min): a
              -- seconds-carrying check-in instant must truncate to its wall
              -- minute, matching the TS engine's minuteOfDayInTz.
              greatest(0,
                (floor(extract(epoch from
                     (coalesce(ovd.manual_checkin_at, rec.checkin_at)
                      at time zone v_tz)) / 60))::int % 1440
                - ((extract(epoch from r.start_time) / 60)::int + r.late_cutoff_minutes)
              ) as late_min,
              -- FR-2 enable-day grace mirrored from day-context.ts computeTracked:
              -- enabled_at on the work date AND its wall-minute > Start AND no
              -- check-in yet → not tracked for reminders today.
              (date(e.enabled_at at time zone v_tz) = v_today
                and (floor(extract(epoch from (e.enabled_at at time zone v_tz))
                          / 60))::int % 1440
                    > (extract(epoch from r.start_time) / 60)::int
                and coalesce(ovd.manual_checkin_at, rec.checkin_at) is null
              ) as grace_skip,
              -- The enrolment pick the outer dedupe makes (exposed only so
              -- `distinct on` can order deterministically — never used in
              -- the reminder arms).
              lower(e.valid) as enrol_from
            from public.attendance_enrolments e
            join public.attendance_office_assignments a
              on a.employee_id = e.employee_id
             and a.tenant_id = v_tenant_id
             and a.valid @> v_today
            join public.attendance_offices o
              on o.id = a.office_id and o.archived_at is null
            join lateral (
              select rrow.*
              from public.attendance_office_rules rrow
              where rrow.office_id = a.office_id
                and rrow.valid @> v_today
              limit 1
            ) r on true
            left join lateral (
              select lrd.state, lrd.leave_request_id
              from public.leave_request_days lrd
              where lrd.employee_id = e.employee_id
                and lrd.leave_date = v_today
                and lrd.state in ('pending', 'approved')
              limit 1
            ) ld on true
            left join public.leave_requests lr
              on lr.id = ld.leave_request_id
             and lr.tenant_id = v_tenant_id
            left join public.attendance_records rec
              on rec.employee_id = e.employee_id
             and rec.work_date = v_today
            left join public.attendance_day_overrides ovd
              on ovd.employee_id = e.employee_id
             and ovd.work_date = v_today
             and ovd.deleted_at is null
            where e.tenant_id = v_tenant_id
              and e.valid @> v_today
          ) inner_facts
          -- Oldest covering period wins (the enrolment pick the TS
          -- reader makes; `distinct on` needs this deterministic tie).
          order by inner_facts.employee_id, inner_facts.enrol_from asc
        ) f
      )
      insert into public.notifications
        (tenant_id, user_id, job_id, event_type, payload,
         entity_type, entity_id, dedupe_key)
      select
        v_tenant_id,
        rem.recipient_id,
        null::uuid,
        rem.event_type,
        rem.payload,
        rem.entity_type,
        rem.entity_id,
        rem.dedupe_key
      from (
        -- SCOPE NOTE (user decision 2026-09-29): reminders model rules
        -- whose Start/Expected end fall inside ONE tenant-local day.
        -- Midnight-crossing schedules are declared OUT OF SCOPE — every
        -- minute here is a wall-minute of v_today compared with
        -- v_now_min of the same local day, so an end past 24:00 would
        -- mis-fire against the wrong half of the day (D1's wrap-around
        -- gap). If that requirement ever lands, add the wrap arms then.
        -- Arm 1: check-in reminder — Start + Late cut-off; Midpoint +
        -- Late cut-off on an approved first-half leave day; approved
        -- full-day leave suppresses; pending leave never suppresses.
        select
          f.employee_id as recipient_id,
          'attendance.reminder_checkin' as event_type,
          jsonb_build_object('workDate', v_today) as payload,
          'attendance' as entity_type,
          f.employee_id as entity_id,
          v_tenant_id || ':attendance.reminder_checkin:'
            || f.employee_id || ':' || v_today as dedupe_key
        from facts f
        where f.is_working_day
          and not f.full_day_leave
          and not f.adjudicated
          and not f.grace_skip
          and f.checkin_at is null
          and v_now_min >= (
            case when f.first_half_leave
                 then f.midpoint_min + f.cutoff
                 else f.start_min + f.cutoff end
          )

        union all

        -- Arm 2: check-out reminder — Expected end + actual late minutes
        -- (late = 0 → due at Expected end; user decision 2026-09-29),
        -- Midpoint + late minutes on an approved second-half leave day.
        select
          f.employee_id,
          'attendance.reminder_checkout',
          jsonb_build_object(
            'workDate', v_today,
            'checkinAt',
            to_char(f.checkin_at at time zone v_tz,
                    'YYYY-MM-DD"T"HH24:MI:SSOF')
          ),
          'attendance',
          f.employee_id,
          v_tenant_id || ':attendance.reminder_checkout:'
            || f.employee_id || ':' || v_today as dedupe_key
        from facts f
        where f.is_working_day
          and not f.adjudicated
          and f.checkin_at is not null
          and f.checkout_at is null
          and f.late_min is not null
          and v_now_min >= (
            case when f.second_half_leave
                 then f.midpoint_min + f.late_min
                 else f.end_min + f.late_min end
          )

        union all

        -- Arm 3: office summary for the owner — at Start + Late cut-off,
        -- one per office per day: how many tracked employees of that
        -- office are on a working day with no check-in and no approved
        -- full-day leave (first-half-leave employees count — their own
        -- reminder just fires later at Midpoint + cut-off).
        select
          v_owner_id,
          'attendance.reminder_not_checked_in',
          jsonb_build_object(
            'officeName', f.office_name,
            'notCheckedInCount', count(*),
            'workDate', v_today
          ),
          'attendance',
          f.office_id,
          v_tenant_id || ':attendance.reminder_not_checked_in:'
            || v_owner_id || ':' || v_today || ':' || f.office_id
        from facts f
        where f.is_working_day
          and not f.full_day_leave
          and not f.adjudicated
          and not f.grace_skip
          and f.checkin_at is null
          and v_now_min >= f.start_min + f.cutoff
        group by f.office_id, f.office_name
        having count(*) > 0
      ) rem
      on conflict (dedupe_key) where dedupe_key is not null do nothing;
    exception
      when others then
        -- One tenant's failure never stops the others (AD-14). The
        -- warning carries the tenant id only — reminders involve no
        -- coordinates (NFR-9/11 hygiene).
        raise warning 'attendance_run_reminders: tenant % failed: %',
          v_tenant_id, sqlerrm;
    end;
  end loop;
end;
$$;


ALTER FUNCTION "public"."attendance_run_reminders"("p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_set_weekly_off_default"("p_tenant_id" "uuid", "p_days" integer[], "p_effective_from" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_today          date;
  v_effective_from date;
  v_days           integer[];
  v_queued_from    date;
begin
  if p_days is null then
    raise exception 'days is required (use an empty array for no day off)'
      using errcode = '23514';
  end if;

  perform public.attendance_lock_tenant(p_tenant_id, true);

  v_today := public.attendance_today(p_tenant_id);
  v_effective_from := greatest(coalesce(p_effective_from, v_today), v_today);

  v_days := coalesce(
    (select array_agg(distinct d order by d) from unnest(p_days) as d),
    '{}'::integer[]
  );

  if cardinality(v_days) = 7 then
    raise exception 'all seven days cannot be weekly offs'
      using errcode = 'PT422',
            hint = 'ATTENDANCE_NO_WORKING_DAYS';
  end if;

  if cardinality(v_days) > 0 then
    select lower(valid) into v_queued_from
      from public.attendance_weekly_off_defaults
      where tenant_id = p_tenant_id
        and lower(valid) > v_today
        and lower(valid) < v_effective_from
        and valid @> v_effective_from
        and days = v_days;

    if v_queued_from is not null then
      delete from public.attendance_weekly_off_defaults
        where tenant_id = p_tenant_id
          and lower(valid) = v_queued_from;

      update public.attendance_weekly_off_defaults
        set valid = daterange(lower(valid), v_effective_from, '[)')
        where tenant_id = p_tenant_id
          and upper(valid) = v_queued_from;
    end if;
  end if;

  if cardinality(v_days) = 0 then
    update public.attendance_weekly_off_defaults r
      set valid = daterange(lower(r.valid), v_effective_from, '[)')
      where r.tenant_id = p_tenant_id
        and upper(r.valid) is not null
        and upper(r.valid) > v_today
        and upper(r.valid) < v_effective_from
        and not exists (
          select 1 from public.attendance_weekly_off_defaults o
          where o.tenant_id = p_tenant_id
            and o.valid && daterange(upper(r.valid), v_effective_from, '[)')
        );
  end if;

  delete from public.attendance_weekly_off_defaults
    where tenant_id = p_tenant_id
      and lower(valid) >= v_effective_from;

  update public.attendance_weekly_off_defaults
    set valid = daterange(lower(valid), v_effective_from, '[)')
    where tenant_id = p_tenant_id
      and valid @> v_effective_from;

  if cardinality(v_days) > 0 then
    insert into public.attendance_weekly_off_defaults (tenant_id, valid, days)
      values (p_tenant_id, daterange(v_effective_from, null, '[)'), v_days);
  end if;

  update public.tenants
    set weekly_off_configured_at = now()
    where id = p_tenant_id
      and weekly_off_configured_at is null;
end;
$$;


ALTER FUNCTION "public"."attendance_set_weekly_off_default"("p_tenant_id" "uuid", "p_days" integer[], "p_effective_from" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_set_weekly_off_override"("p_tenant_id" "uuid", "p_employee_id" "uuid", "p_days" integer[], "p_effective_from" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_today          date;
  v_effective_from date;
  v_days           integer[];
  v_queued_from    date;
begin
  if p_days is null then
    raise exception 'days is required (use an empty array for no day off)'
      using errcode = '23514';
  end if;

  perform public.attendance_lock_tenant(p_tenant_id, true);

  v_today := public.attendance_today(p_tenant_id);
  v_effective_from := greatest(coalesce(p_effective_from, v_today), v_today);

  if not exists (
    select 1 from public.users
    where id = p_employee_id
      and tenant_id = p_tenant_id
  ) then
    raise exception 'employee % not found in tenant %', p_employee_id, p_tenant_id
      using errcode = 'PT404',
            hint = 'ATTENDANCE_EMPLOYEE_NOT_FOUND';
  end if;

  if not exists (
    select 1 from public.users
    where id = p_employee_id
      and tenant_id = p_tenant_id
      and status = 'active'
  ) then
    raise exception 'employee % is not active in tenant %', p_employee_id, p_tenant_id
      using errcode = 'PT422',
            hint = 'ATTENDANCE_EMPLOYEE_NOT_ACTIVE';
  end if;

  v_days := coalesce(
    (select array_agg(distinct d order by d) from unnest(p_days) as d),
    '{}'::integer[]
  );

  if cardinality(v_days) = 7 then
    raise exception 'all seven days cannot be weekly offs'
      using errcode = 'PT422',
            hint = 'ATTENDANCE_NO_WORKING_DAYS';
  end if;

  select lower(valid) into v_queued_from
    from public.attendance_weekly_off_overrides
    where employee_id = p_employee_id
      and lower(valid) > v_today
      and lower(valid) < v_effective_from
      and valid @> v_effective_from
      and days = v_days;

  if v_queued_from is not null then
    delete from public.attendance_weekly_off_overrides
      where employee_id = p_employee_id
        and lower(valid) = v_queued_from;

    update public.attendance_weekly_off_overrides
      set valid = daterange(lower(valid), v_effective_from, '[)')
      where employee_id = p_employee_id
        and upper(valid) = v_queued_from;
  end if;

  delete from public.attendance_weekly_off_overrides
    where employee_id = p_employee_id
      and lower(valid) >= v_effective_from;

  update public.attendance_weekly_off_overrides
    set valid = daterange(lower(valid), v_effective_from, '[)')
    where employee_id = p_employee_id
      and valid @> v_effective_from;

  insert into public.attendance_weekly_off_overrides
    (tenant_id, employee_id, valid, days)
    values (p_tenant_id, p_employee_id, daterange(v_effective_from, null, '[)'), v_days);
end;
$$;


ALTER FUNCTION "public"."attendance_set_weekly_off_override"("p_tenant_id" "uuid", "p_employee_id" "uuid", "p_days" integer[], "p_effective_from" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_start_setup"("p_tenant_id" "uuid", "p_actor_id" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  insert into public.attendance_settings (tenant_id)
  values (p_tenant_id)
  on conflict (tenant_id) do nothing;

  insert into public.attendance_setup_progress (tenant_id, current_step)
  values (p_tenant_id, 'offices')
  on conflict (tenant_id) do nothing;
$$;


ALTER FUNCTION "public"."attendance_start_setup"("p_tenant_id" "uuid", "p_actor_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_today"("p_tenant_id" "uuid") RETURNS "date"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tz text;
begin
  select timezone into v_tz from public.tenants where id = p_tenant_id;
  if v_tz is null then
    raise exception 'tenant % not found', p_tenant_id
      using errcode = 'PT404',
            hint = 'ATTENDANCE_TENANT_NOT_FOUND';
  end if;
  return (now() at time zone v_tz)::date;
end;
$$;


ALTER FUNCTION "public"."attendance_today"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_update_holiday"("p_tenant_id" "uuid", "p_holiday_id" "uuid", "p_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  perform public.attendance_lock_tenant(p_tenant_id, true);

  perform public.attendance_today(p_tenant_id);

  update public.holidays
    set name = p_name
    where id = p_holiday_id
      and tenant_id = p_tenant_id;

  if not found then
    raise exception 'holiday % not found in tenant %', p_holiday_id, p_tenant_id
      using errcode = 'PT404',
            hint = 'ATTENDANCE_HOLIDAY_NOT_FOUND';
  end if;
end;
$$;


ALTER FUNCTION "public"."attendance_update_holiday"("p_tenant_id" "uuid", "p_holiday_id" "uuid", "p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attendance_update_office_rules"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_office_id" "uuid", "p_start_time" time without time zone, "p_end_time" time without time zone, "p_late_cutoff_minutes" integer, "p_full_day_hours" numeric, "p_half_day_hours" numeric) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_today           date;
  v_effective_from  date;
begin
  perform public.attendance_lock_tenant(p_tenant_id, true);

  v_today := public.attendance_today(p_tenant_id);
  v_effective_from := v_today + 1;

  if not exists (
    select 1 from public.attendance_offices
    where id = p_office_id
      and tenant_id = p_tenant_id
      and archived_at is null
  ) then
    raise exception 'office % not found in tenant %', p_office_id, p_tenant_id
      using errcode = 'PT404',
            hint = 'ATTENDANCE_OFFICE_NOT_FOUND';
  end if;

  delete from public.attendance_office_rules
    where office_id = p_office_id
      and lower(valid) >= v_effective_from;

  update public.attendance_office_rules
    set valid = daterange(lower(valid), v_effective_from, '[)')
    where office_id = p_office_id
      and valid @> v_effective_from;

  insert into public.attendance_office_rules
    (office_id, tenant_id, valid, start_time, end_time, late_cutoff_minutes, full_day_hours, half_day_hours)
    values (
      p_office_id,
      p_tenant_id,
      daterange(v_effective_from, null, '[)'),
      p_start_time,
      p_end_time,
      p_late_cutoff_minutes,
      p_full_day_hours,
      p_half_day_hours
    );
end;
$$;


ALTER FUNCTION "public"."attendance_update_office_rules"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_office_id" "uuid", "p_start_time" time without time zone, "p_end_time" time without time zone, "p_late_cutoff_minutes" integer, "p_full_day_hours" numeric, "p_half_day_hours" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_attachment"("p_upload_id" "uuid", "p_job_id" "uuid", "p_tenant_id" "uuid", "p_size_bytes" integer, "p_actor_id" "uuid") RETURNS TABLE("attachment_id" "uuid", "attachment_type" "text", "created_at" timestamp with time zone, "already_existed" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_upload      attachment_uploads%ROWTYPE;
  v_att_id      UUID;
  v_created_at  TIMESTAMPTZ;
  v_photo_count BIGINT;
  v_existing_id UUID;
  v_steps       JSONB;
  v_i           INT;
  v_n           INT;
  v_photo_idx   INT;
  v_photo_key   TEXT;
  v_prev_key    TEXT;
  v_sets_status TEXT;
  v_current     TEXT;
BEGIN
  SELECT * INTO v_upload
  FROM attachment_uploads
  WHERE id = p_upload_id
    AND job_id = p_job_id
    AND tenant_id = p_tenant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'UPLOAD_NOT_FOUND';
  END IF;

  IF v_upload.status = 'confirmed' THEN
    SELECT a.id, a.created_at
      INTO v_att_id, v_created_at
      FROM attachments a
      WHERE a.upload_id = p_upload_id;

    RETURN QUERY SELECT v_att_id, v_upload.attachment_type, v_created_at, TRUE;
    RETURN;
  END IF;

  IF v_upload.expires_at < now() THEN
    UPDATE attachment_uploads SET status = 'expired' WHERE id = p_upload_id;
    RAISE EXCEPTION 'UPLOAD_EXPIRED';
  END IF;

  IF v_upload.attachment_type = 'signature' THEN
    SELECT att.upload_id INTO v_existing_id
    FROM attachments att
    WHERE att.job_id = p_job_id
      AND att.tenant_id = p_tenant_id
      AND att.attachment_type = 'signature';

    UPDATE attachments att
    SET r2_key     = v_upload.r2_key,
        upload_id  = p_upload_id,
        size_bytes = p_size_bytes,
        created_at = now()
    WHERE att.job_id = p_job_id
      AND att.tenant_id = p_tenant_id
      AND att.attachment_type = 'signature'
    RETURNING att.id INTO v_att_id;

    IF FOUND THEN
      INSERT INTO activity_logs (job_id, tenant_id, event_type, actor_id, metadata)
        VALUES (
          p_job_id, p_tenant_id, 'conflict_resolved', p_actor_id,
          jsonb_build_object(
            'reason',              'last_write_wins',
            'replaced_upload_id',  v_existing_id::text
          )
        );
    ELSE
      BEGIN
        INSERT INTO attachments (job_id, tenant_id, upload_id, r2_key, attachment_type, size_bytes)
          VALUES (p_job_id, p_tenant_id, p_upload_id, v_upload.r2_key, 'signature', p_size_bytes)
          RETURNING id INTO v_att_id;
      EXCEPTION WHEN unique_violation THEN
        SELECT a.id, a.upload_id INTO v_att_id, v_existing_id
        FROM attachments a
        WHERE a.job_id = p_job_id
          AND a.tenant_id = p_tenant_id
          AND a.attachment_type = 'signature';

        INSERT INTO activity_logs (job_id, tenant_id, event_type, actor_id, metadata)
          VALUES (
            p_job_id, p_tenant_id, 'conflict_resolved', p_actor_id,
            jsonb_build_object(
              'reason',               'last_write_wins',
              'replaced_upload_id',   p_upload_id::text,
              'winning_upload_id',    v_existing_id::text
            )
          );
      END;
    END IF;

    SELECT a.created_at INTO v_created_at FROM attachments a WHERE a.id = v_att_id;
  ELSE
    SELECT COUNT(*) INTO v_photo_count
    FROM attachments att
    WHERE att.job_id = p_job_id AND att.tenant_id = p_tenant_id
      AND att.attachment_type = 'photo';

    IF v_photo_count >= 5 THEN
      RAISE EXCEPTION 'PHOTO_LIMIT_EXCEEDED';
    END IF;

    INSERT INTO attachments (job_id, tenant_id, upload_id, r2_key, attachment_type, size_bytes)
      VALUES (p_job_id, p_tenant_id, p_upload_id, v_upload.r2_key, 'photo', p_size_bytes)
      RETURNING id INTO v_att_id;

    SELECT a.created_at INTO v_created_at FROM attachments a WHERE a.id = v_att_id;
  END IF;

  UPDATE attachment_uploads SET status = 'confirmed' WHERE id = p_upload_id;

  IF v_upload.attachment_type = 'photo' THEN
    SELECT t.steps INTO v_steps
    FROM jobs j
    JOIN workflow_templates t
      ON t.id = j.workflow_template_id AND t.version = j.workflow_template_version
    WHERE j.id = p_job_id AND j.tenant_id = p_tenant_id;

    IF v_steps IS NOT NULL THEN
      v_n := jsonb_array_length(v_steps);
      FOR v_i IN 0 .. v_n - 1 LOOP
        IF v_steps -> v_i ->> 'advances_on' = 'photo_confirm' THEN
          v_photo_idx := v_i;
          v_photo_key := v_steps -> v_i ->> 'key';
          v_sets_status := v_steps -> v_i ->> 'sets_status';
          EXIT;
        END IF;
      END LOOP;

      IF v_photo_key IS NOT NULL THEN
        v_prev_key := CASE
          WHEN v_photo_idx = 0 THEN NULL
          ELSE v_steps -> (v_photo_idx - 1) ->> 'key'
        END;

        SELECT current_step INTO v_current
        FROM jobs
        WHERE id = p_job_id AND tenant_id = p_tenant_id;

        IF v_current IS NOT DISTINCT FROM v_prev_key THEN
          BEGIN
            PERFORM advance_workflow_step(
              p_job_id, p_tenant_id, p_actor_id,
              v_photo_key, v_sets_status, v_prev_key
            );
          EXCEPTION WHEN SQLSTATE 'PT409' THEN
            RAISE LOG 'confirm_attachment: auto-advance to % skipped for job % (job terminal or step moved concurrently)',
              v_photo_key, p_job_id;
          END;
        END IF;
      END IF;
    ELSE
      RAISE LOG 'confirm_attachment: no stamped workflow template for job % (auto-advance skipped)',
        p_job_id;
    END IF;
  END IF;

  RETURN QUERY SELECT v_att_id, v_upload.attachment_type, v_created_at, FALSE;
END $$;


ALTER FUNCTION "public"."confirm_attachment"("p_upload_id" "uuid", "p_job_id" "uuid", "p_tenant_id" "uuid", "p_size_bytes" integer, "p_actor_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_job_with_log"("p_tenant_id" "uuid", "p_customer_id" "uuid", "p_technician_id" "uuid", "p_service_location" "text", "p_skill_id" "uuid", "p_scheduled_start" timestamp with time zone, "p_scheduled_end" timestamp with time zone, "p_description" "text", "p_priority" "text", "p_notes_for_technician" "text", "p_actor_id" "uuid", "p_year" integer) RETURNS SETOF "public"."jobs"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_seq        INT;
  v_job_number TEXT;
  v_job_id     UUID := gen_random_uuid();
  v_template_id      UUID;
  v_template_version INT;
BEGIN
  SELECT id, version
    INTO v_template_id, v_template_version
    FROM workflow_templates
   WHERE skill_id = p_skill_id
   ORDER BY version DESC
   LIMIT 1;

  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'No workflow template found for skill %', p_skill_id;
  END IF;

  v_seq := increment_job_counter(p_tenant_id, p_year);
  v_job_number := 'JB-' || p_year::text || '-' || lpad(v_seq::text, 4, '0');

  INSERT INTO jobs (
    id, tenant_id, job_number, customer_id, technician_id,
    service_location, skill_id, workflow_template_id,
    workflow_template_version, scheduled_start, scheduled_end,
    status, current_step, priority,
    description, notes_for_technician
  ) VALUES (
    v_job_id, p_tenant_id, v_job_number, p_customer_id, p_technician_id,
    p_service_location, p_skill_id, v_template_id,
    v_template_version, p_scheduled_start, p_scheduled_end,
    'scheduled', NULL, COALESCE(p_priority, 'normal'),
    p_description, p_notes_for_technician
  );

  INSERT INTO activity_logs (job_id, tenant_id, event_type, actor_id)
  VALUES (v_job_id, p_tenant_id, 'job_created', p_actor_id);

  RETURN QUERY SELECT * FROM jobs WHERE id = v_job_id;
END $$;


ALTER FUNCTION "public"."create_job_with_log"("p_tenant_id" "uuid", "p_customer_id" "uuid", "p_technician_id" "uuid", "p_service_location" "text", "p_skill_id" "uuid", "p_scheduled_start" timestamp with time zone, "p_scheduled_end" timestamp with time zone, "p_description" "text", "p_priority" "text", "p_notes_for_technician" "text", "p_actor_id" "uuid", "p_year" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_job_counter"("p_tenant_id" "uuid", "p_year" integer) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_seq INT;
BEGIN
  INSERT INTO job_sequences (tenant_id, year, last_seq)
  VALUES (p_tenant_id, p_year, 1)
  ON CONFLICT (tenant_id, year)
  DO UPDATE SET last_seq = job_sequences.last_seq + 1
  RETURNING last_seq INTO v_seq;
  RETURN v_seq;
END $$;


ALTER FUNCTION "public"."increment_job_counter"("p_tenant_id" "uuid", "p_year" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."leave_request_days_state_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.state = old.state then
    return new;
  end if;
  if old.state = 'pending' and new.state in ('approved','rejected','cancelled') then
    return new;
  end if;
  if old.state = 'approved' and new.state in ('revoked','cancelled') then
    return new;
  end if;
  raise exception
    'Illegal leave day transition % -> %', old.state, new.state
    using errcode = 'PT422', hint = 'LEAVE_INVALID_TRANSITION';
end;
$$;


ALTER FUNCTION "public"."leave_request_days_state_guard"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notifications_broadcast_changes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM realtime.broadcast_changes(
    'user:' || NEW.user_id || ':notifications',
    TG_OP, TG_OP, TG_TABLE_NAME, TG_TABLE_SCHEMA, NEW, OLD
  );
  RETURN NULL;
END $$;


ALTER FUNCTION "public"."notifications_broadcast_changes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_requests_in_flight_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_in_flight integer;
  v_max constant integer := 3;  -- NFR-3
begin
  -- Count-neutral transitions skip the check entirely: the worker's
  -- queued→generating claim and lease recovery keep the row inside the
  -- in-flight set (already counted), and a terminal stamp only frees a
  -- slot. Re-checking those would falsely 429 the finishing stamp of the
  -- third in-flight row.
  if tg_op = 'UPDATE'
     and (
       new.status not in ('queued', 'generating')
       or old.status in ('queued', 'generating')
     )
  then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.tenant_id::text, 0));

  select count(*) into v_in_flight
  from report_requests
  where tenant_id = new.tenant_id
    and status in ('queued', 'generating');

  if v_in_flight >= v_max then
    raise exception 'tenant % already has % in-flight report requests',
      new.tenant_id, v_max
      using errcode = 'PT429';
  end if;

  return new;
end $$;


ALTER FUNCTION "public"."report_requests_in_flight_guard"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_employee_code"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_seq INT;
BEGIN
  IF NEW.tenant_id IS NULL OR NEW.employee_code IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.employee_code IS NOT NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.employee_sequences (tenant_id, last_seq)
  VALUES (NEW.tenant_id, 1)
  ON CONFLICT (tenant_id)
  DO UPDATE SET last_seq = public.employee_sequences.last_seq + 1
  RETURNING last_seq INTO v_seq;

  NEW.employee_code := 'EMP-' || lpad(v_seq::text, GREATEST(3, length(v_seq::text)), '0');
  RETURN NEW;
END $$;


ALTER FUNCTION "public"."set_employee_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."setup_tenant_for_owner"("p_user_id" "uuid", "p_company_name" "text", "p_gstin" "text", "p_address" "text", "p_state_code" "text", "p_upi_vpa" "text") RETURNS TABLE("id" "uuid", "owner_id" "uuid", "company_name" "text", "gstin" "text", "address" "text", "state_code" "text", "upi_vpa" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "inserted" boolean)
    LANGUAGE "plpgsql"
    AS $$
#variable_conflict use_column
DECLARE
  v_tenant_id  UUID;
  v_inserted   BOOLEAN;
BEGIN
  INSERT INTO tenants (
    owner_id, company_name, gstin, address, state_code, upi_vpa
  )
  VALUES (
    p_user_id, p_company_name, p_gstin, p_address, p_state_code, p_upi_vpa
  )
  ON CONFLICT (owner_id) DO UPDATE SET
    company_name = EXCLUDED.company_name,
    gstin        = EXCLUDED.gstin,
    address      = EXCLUDED.address,
    state_code   = EXCLUDED.state_code,
    upi_vpa      = EXCLUDED.upi_vpa,
    updated_at   = now()
  RETURNING tenants.id, (xmax = 0) INTO v_tenant_id, v_inserted;

  IF v_inserted THEN
    UPDATE users
       SET tenant_id = v_tenant_id,
           updated_at = now()
     WHERE id = p_user_id
       AND tenant_id IS NULL;
  END IF;

  RETURN QUERY
    SELECT t.id, t.owner_id, t.company_name, t.gstin, t.address, t.state_code,
           t.upi_vpa, t.created_at, t.updated_at, v_inserted
      FROM tenants t
     WHERE t.id = v_tenant_id;
END $$;


ALTER FUNCTION "public"."setup_tenant_for_owner"("p_user_id" "uuid", "p_company_name" "text", "p_gstin" "text", "p_address" "text", "p_state_code" "text", "p_upi_vpa" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tenants_timezone_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_timezone_names
    where name = new.timezone
      and position('/' in name) > 0
  ) then
    raise exception 'invalid tenant timezone "%"', new.timezone
      using errcode = 'PT422',
            hint = 'ATTENDANCE_INVALID_TIMEZONE';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."tenants_timezone_guard"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_job_with_log"("p_job_id" "uuid", "p_tenant_id" "uuid", "p_actor_id" "uuid", "p_cancel" boolean, "p_description" "text", "p_scheduled_start" timestamp with time zone, "p_scheduled_end" timestamp with time zone, "p_notes_for_technician" "text", "p_technician_id" "uuid", "p_priority" "text") RETURNS SETOF "public"."jobs"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_job      jobs%ROWTYPE;
  v_old_tech UUID;
BEGIN
  -- Tenant-scoped row lock. A missing/cross-tenant row returns the empty set,
  -- which the app maps to 404 (cross-tenant is indistinguishable from not-found).
  SELECT * INTO v_job
  FROM jobs
  WHERE id = p_job_id AND tenant_id = p_tenant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Only a `scheduled` job is modifiable. Raise with a custom SQLSTATE the app
  -- maps to 409 JOB_NOT_MODIFIABLE. PT409 is in the PostgREST PTxxx convention
  -- (last 3 digits = HTTP status) but the app reads error.code directly.
  IF v_job.status <> 'scheduled' THEN
    RAISE EXCEPTION 'job % is not modifiable in status %', p_job_id, v_job.status
      USING ERRCODE = 'PT409';
  END IF;

  IF p_cancel THEN
    UPDATE jobs
    SET status = 'cancelled', updated_at = now()
    WHERE id = p_job_id;

    INSERT INTO activity_logs (job_id, tenant_id, event_type, actor_id)
    VALUES (p_job_id, p_tenant_id, 'job_cancelled', p_actor_id);
  ELSE
    v_old_tech := v_job.technician_id;

    -- Reject an inverted schedule window using the EFFECTIVE values (after the
    -- COALESCE patch), so a one-sided edit (only start, or only end) can't push
    -- the stored window past the unchanged bound. Mapped to 422 by the app.
    IF COALESCE(p_scheduled_end, v_job.scheduled_end) IS NOT NULL
       AND COALESCE(p_scheduled_end, v_job.scheduled_end)
         < COALESCE(p_scheduled_start, v_job.scheduled_start) THEN
      RAISE EXCEPTION 'scheduled_end before scheduled_start'
        USING ERRCODE = 'PT422';
    END IF;

    -- COALESCE: a NULL param leaves the column unchanged (PATCH semantics).
    -- Clearing a nullable field back to NULL is intentionally out of scope.
    UPDATE jobs
    SET description          = COALESCE(p_description, description),
        scheduled_start      = COALESCE(p_scheduled_start, scheduled_start),
        scheduled_end        = COALESCE(p_scheduled_end, scheduled_end),
        notes_for_technician = COALESCE(p_notes_for_technician, notes_for_technician),
        technician_id        = COALESCE(p_technician_id, technician_id),
        priority             = COALESCE(p_priority, priority),
        updated_at           = now()
    WHERE id = p_job_id;

    -- Reassignment log only when the technician actually changed. IS DISTINCT
    -- FROM is null-safe (the IS NOT NULL guard keeps an omitted technician from
    -- logging a spurious reassignment).
    IF p_technician_id IS NOT NULL AND p_technician_id IS DISTINCT FROM v_old_tech THEN
      INSERT INTO activity_logs (job_id, tenant_id, event_type, actor_id, metadata)
      VALUES (
        p_job_id, p_tenant_id, 'job_reassigned', p_actor_id,
        jsonb_build_object(
          'previousTechnicianId', v_old_tech,
          'newTechnicianId', p_technician_id
        )
      );
    END IF;
  END IF;

  RETURN QUERY SELECT * FROM jobs WHERE id = p_job_id AND tenant_id = p_tenant_id;
END $$;


ALTER FUNCTION "public"."update_job_with_log"("p_job_id" "uuid", "p_tenant_id" "uuid", "p_actor_id" "uuid", "p_cancel" boolean, "p_description" "text", "p_scheduled_start" timestamp with time zone, "p_scheduled_end" timestamp with time zone, "p_notes_for_technician" "text", "p_technician_id" "uuid", "p_priority" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."workflow_steps_valid"("p_steps" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    AS $_$
DECLARE
  v_step  JSONB;
  v_i     INT;
  v_n     INT;
  v_keys  TEXT[];
  v_key   TEXT;
BEGIN
  IF p_steps IS NULL OR jsonb_typeof(p_steps) <> 'array'
     OR jsonb_array_length(p_steps) = 0 THEN
    RETURN FALSE;
  END IF;

  v_n := jsonb_array_length(p_steps);

  FOR v_i IN 0 .. v_n - 1 LOOP
    v_step := p_steps -> v_i;

    IF jsonb_typeof(v_step) <> 'object' THEN
      RETURN FALSE;
    END IF;

    v_key := v_step ->> 'key';
    IF v_key IS NULL OR v_key !~ '^[a-z0-9_]{1,64}$' THEN
      RETURN FALSE;
    END IF;
    IF v_key = ANY (v_keys) THEN
      RETURN FALSE;
    END IF;
    v_keys := array_append(v_keys, v_key);

    IF v_step ->> 'label' IS NULL OR btrim(v_step ->> 'label') = '' THEN
      RETURN FALSE;
    END IF;

    IF jsonb_typeof(v_step -> 'requires_photo') <> 'boolean'
       OR jsonb_typeof(v_step -> 'requires_signature') <> 'boolean' THEN
      RETURN FALSE;
    END IF;

    -- requires_location is optional; if present, must be boolean
    IF v_step ? 'requires_location'
       AND jsonb_typeof(v_step -> 'requires_location') <> 'boolean' THEN
      RETURN FALSE;
    END IF;

    IF v_step ? 'sets_status'
       AND jsonb_typeof(v_step -> 'sets_status') <> 'null'
       AND v_step ->> 'sets_status' NOT IN ('in_progress', 'completed') THEN
      RETURN FALSE;
    END IF;

    IF v_step ? 'advances_on'
       AND jsonb_typeof(v_step -> 'advances_on') <> 'null'
       AND v_step ->> 'advances_on' NOT IN ('photo_confirm') THEN
      RETURN FALSE;
    END IF;
  END LOOP;

  RETURN TRUE;
END $_$;


ALTER FUNCTION "public"."workflow_steps_valid"("p_steps" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."activity_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "job_id" "uuid" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "actor_id" "uuid",
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."activity_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_config" (
    "key" "text" NOT NULL,
    "value" "jsonb" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."app_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attachment_uploads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "job_id" "uuid" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "r2_key" "text" NOT NULL,
    "attachment_type" "text" NOT NULL,
    "mime_type" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attachment_uploads_attachment_type_check" CHECK (("attachment_type" = ANY (ARRAY['photo'::"text", 'signature'::"text"]))),
    CONSTRAINT "attachment_uploads_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'confirmed'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."attachment_uploads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attachments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "job_id" "uuid" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "upload_id" "uuid",
    "r2_key" "text" NOT NULL,
    "attachment_type" "text" NOT NULL,
    "size_bytes" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attachments_attachment_type_check" CHECK (("attachment_type" = ANY (ARRAY['photo'::"text", 'signature'::"text"])))
);


ALTER TABLE "public"."attachments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_enrolments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "valid" "daterange" NOT NULL,
    "enabled_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_enrolments_valid_check" CHECK ((NOT "isempty"("valid"))),
    CONSTRAINT "attendance_enrolments_valid_open_end_check" CHECK ((("upper"("valid") IS NULL) OR ("upper"("valid") < 'infinity'::"date")))
);


ALTER TABLE "public"."attendance_enrolments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_office_assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "office_id" "uuid" NOT NULL,
    "valid" "daterange" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_office_assignments_valid_check" CHECK ((NOT "isempty"("valid"))),
    CONSTRAINT "attendance_office_assignments_valid_open_end_check" CHECK ((("upper"("valid") IS NULL) OR ("upper"("valid") < 'infinity'::"date")))
);


ALTER TABLE "public"."attendance_office_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_offices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "radius_m" integer NOT NULL,
    "archived_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "formatted_address" "text",
    CONSTRAINT "attendance_offices_formatted_address_len" CHECK ((("formatted_address" IS NULL) OR (("char_length"("btrim"("formatted_address")) >= 1) AND ("char_length"("btrim"("formatted_address")) <= 500)))),
    CONSTRAINT "attendance_offices_latitude_check" CHECK ((("latitude" >= ('-90'::integer)::double precision) AND ("latitude" <= (90)::double precision))),
    CONSTRAINT "attendance_offices_longitude_check" CHECK ((("longitude" >= ('-180'::integer)::double precision) AND ("longitude" <= (180)::double precision))),
    CONSTRAINT "attendance_offices_radius_m_check" CHECK ((("radius_m" >= 50) AND ("radius_m" <= 1000)))
);


ALTER TABLE "public"."attendance_offices" OWNER TO "postgres";


COMMENT ON COLUMN "public"."attendance_offices"."formatted_address" IS 'Display address of the office pin (client-supplied, never used for geofence checks); null when none was saved.';



CREATE TABLE IF NOT EXISTS "public"."attendance_onboarding" (
    "employee_id" "uuid" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "onboarded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."attendance_onboarding" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_settings" (
    "tenant_id" "uuid" NOT NULL,
    "enabled" boolean DEFAULT false NOT NULL,
    "setup_completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."attendance_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."leave_request_days" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "leave_request_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "leave_date" "date" NOT NULL,
    "state" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "leave_request_days_state_check" CHECK (("state" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text", 'cancelled'::"text", 'revoked'::"text"])))
);


ALTER TABLE "public"."leave_request_days" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text",
    "role" "text" NOT NULL,
    "tenant_id" "uuid",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "country_code" "text" NOT NULL,
    "phone_number" "text" NOT NULL,
    "employee_code" "text",
    CONSTRAINT "users_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'technician'::"text"]))),
    CONSTRAINT "users_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'invited'::"text"])))
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."attendance_access_state" WITH ("security_invoker"='true') AS
 SELECT "u"."id" AS "user_id",
    "u"."tenant_id",
    (COALESCE("s"."enabled", false) AND ("s"."setup_completed_at" IS NOT NULL)) AS "attendance_enabled",
        CASE
            WHEN ((COALESCE("s"."enabled", false) IS FALSE) OR ("s"."setup_completed_at" IS NULL)) THEN 'none'::"text"
            WHEN ("cur"."period_start" IS NOT NULL) THEN 'active'::"text"
            WHEN ("nx"."next_start" IS NOT NULL) THEN 'upcoming'::"text"
            WHEN ("past"."seen" IS NOT NULL) THEN 'history_only'::"text"
            ELSE 'none'::"text"
        END AS "access_state",
        CASE
            WHEN ("cur"."period_start" IS NOT NULL) THEN "cur"."period_start"
            WHEN ("nx"."next_start" IS NOT NULL) THEN "nx"."next_start"
            ELSE NULL::"date"
        END AS "attendance_start_date",
    "cur"."enabled_at",
    "ob"."onboarded_at",
    "a"."office_id",
    "o"."name" AS "office_name",
        CASE
            WHEN (("cur"."period_start" IS NULL) AND ("nx"."next_start" IS NULL)) THEN ( SELECT ("max"("upper"("e"."valid")) - 1)
               FROM "public"."attendance_enrolments" "e"
              WHERE (("e"."employee_id" = "u"."id") AND ("upper"("e"."valid") <= "public"."attendance_today"("u"."tenant_id")) AND ("upper"("e"."valid") < 'infinity'::"date")))
            ELSE NULL::"date"
        END AS "attendance_ended_on",
        CASE
            WHEN (COALESCE("s"."enabled", false) AND ("s"."setup_completed_at" IS NOT NULL) AND ("u"."role" = 'owner'::"text")) THEN ( SELECT "count"(DISTINCT "d"."leave_request_id") AS "count"
               FROM "public"."leave_request_days" "d"
              WHERE (("d"."tenant_id" = "u"."tenant_id") AND ("d"."state" = 'pending'::"text")))
            ELSE (0)::bigint
        END AS "pending_leave_requests"
   FROM ((((((("public"."users" "u"
     LEFT JOIN "public"."attendance_settings" "s" ON (("s"."tenant_id" = "u"."tenant_id")))
     LEFT JOIN "public"."attendance_onboarding" "ob" ON (("ob"."employee_id" = "u"."id")))
     LEFT JOIN LATERAL ( SELECT "e"."employee_id",
            "lower"("e"."valid") AS "period_start",
            "e"."enabled_at"
           FROM "public"."attendance_enrolments" "e"
          WHERE (("e"."employee_id" = "u"."id") AND ("e"."valid" @> "public"."attendance_today"("u"."tenant_id")))
         LIMIT 1) "cur" ON (true))
     LEFT JOIN LATERAL ( SELECT "min"("lower"("e"."valid")) AS "next_start"
           FROM "public"."attendance_enrolments" "e"
          WHERE (("e"."employee_id" = "u"."id") AND ("lower"("e"."valid") > "public"."attendance_today"("u"."tenant_id")))) "nx" ON (true))
     LEFT JOIN LATERAL ( SELECT 1 AS "seen"
           FROM "public"."attendance_enrolments" "e"
          WHERE (("e"."employee_id" = "u"."id") AND ("upper"("e"."valid") <= "public"."attendance_today"("u"."tenant_id")))
         LIMIT 1) "past" ON (true))
     LEFT JOIN LATERAL ( SELECT "a_1"."office_id"
           FROM "public"."attendance_office_assignments" "a_1"
          WHERE (("a_1"."employee_id" = "u"."id") AND ("a_1"."valid" @>
                CASE
                    WHEN ("cur"."period_start" IS NOT NULL) THEN "public"."attendance_today"("u"."tenant_id")
                    WHEN ("nx"."next_start" IS NOT NULL) THEN "nx"."next_start"
                    ELSE "public"."attendance_today"("u"."tenant_id")
                END))
         LIMIT 1) "a" ON (true))
     LEFT JOIN "public"."attendance_offices" "o" ON ((("o"."id" = "a"."office_id") AND ("o"."archived_at" IS NULL))))
  WHERE ("u"."tenant_id" IS NOT NULL);


ALTER VIEW "public"."attendance_access_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_attempts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "request_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "outcome" "text" NOT NULL,
    "latitude" double precision,
    "longitude" double precision,
    "accuracy_m" double precision,
    "distance_m" double precision,
    "radius_m" integer,
    "mocked" boolean,
    "provider" "text",
    "fix_age_ms" integer,
    "blocked_until" timestamp with time zone,
    "attempted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "acknowledged_at" timestamp with time zone,
    CONSTRAINT "attendance_attempts_kind_check" CHECK (("kind" = ANY (ARRAY['check_in'::"text", 'check_out'::"text"]))),
    CONSTRAINT "attendance_attempts_outcome_check" CHECK (("outcome" = ANY (ARRAY['ok'::"text", 'too_far'::"text", 'low_accuracy'::"text", 'mocked'::"text", 'stale_fix'::"text", 'rate_limited'::"text", 'not_tracked'::"text", 'already_checked_in'::"text", 'already_checked_out'::"text", 'not_checked_in'::"text", 'leave_confirmation_required'::"text"])))
);


ALTER TABLE "public"."attendance_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_corrections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "work_date" "date" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "note" "text" NOT NULL,
    "old_value" "jsonb" NOT NULL,
    "new_value" "jsonb" NOT NULL,
    "seq" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_corrections_note_check" CHECK ((("char_length"("note") >= 1) AND ("char_length"("note") <= 500)))
);


ALTER TABLE "public"."attendance_corrections" OWNER TO "postgres";


ALTER TABLE "public"."attendance_corrections" ALTER COLUMN "seq" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."attendance_corrections_seq_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."attendance_day_overrides" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "work_date" "date" NOT NULL,
    "status" "text",
    "manual_checkin_at" timestamp with time zone,
    "manual_checkout_at" timestamp with time zone,
    "deleted_at" timestamp with time zone,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_day_overrides_has_value_check" CHECK ((("status" IS NOT NULL) OR ("manual_checkin_at" IS NOT NULL) OR ("manual_checkout_at" IS NOT NULL))),
    CONSTRAINT "attendance_day_overrides_pair_check" CHECK ((("status" IS NULL) OR (("manual_checkin_at" IS NULL) AND ("manual_checkout_at" IS NULL)))),
    CONSTRAINT "attendance_day_overrides_status_check" CHECK (("status" = ANY (ARRAY['present'::"text", 'half_day'::"text", 'absent'::"text"]))),
    CONSTRAINT "attendance_day_overrides_time_order_check" CHECK ((("manual_checkout_at" IS NULL) OR ("manual_checkin_at" IS NULL) OR ("manual_checkout_at" > "manual_checkin_at")))
);


ALTER TABLE "public"."attendance_day_overrides" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_office_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "office_id" "uuid" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "valid" "daterange" NOT NULL,
    "start_time" time without time zone NOT NULL,
    "end_time" time without time zone NOT NULL,
    "late_cutoff_minutes" integer NOT NULL,
    "full_day_hours" numeric(4,2) NOT NULL,
    "half_day_hours" numeric(4,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_office_rules_check" CHECK (("end_time" > "start_time")),
    CONSTRAINT "attendance_office_rules_check1" CHECK ((("half_day_hours" > (0)::numeric) AND ("half_day_hours" < "full_day_hours"))),
    CONSTRAINT "attendance_office_rules_full_day_hours_check" CHECK (("full_day_hours" > (0)::numeric)),
    CONSTRAINT "attendance_office_rules_late_cutoff_minutes_check" CHECK ((("late_cutoff_minutes" >= 0) AND ("late_cutoff_minutes" <= 120))),
    CONSTRAINT "attendance_office_rules_valid_check" CHECK ((NOT "isempty"("valid")))
);


ALTER TABLE "public"."attendance_office_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "work_date" "date" NOT NULL,
    "office_id" "uuid" NOT NULL,
    "office_rules_id" "uuid",
    "radius_m" integer NOT NULL,
    "checkin_at" timestamp with time zone NOT NULL,
    "checkin_attempt_id" "uuid" NOT NULL,
    "checkin_lat" double precision NOT NULL,
    "checkin_lng" double precision NOT NULL,
    "checkin_accuracy_m" double precision NOT NULL,
    "checkin_distance_m" double precision NOT NULL,
    "checkin_mocked" boolean NOT NULL,
    "checkin_provider" "text",
    "checkout_at" timestamp with time zone,
    "checkout_attempt_id" "uuid",
    "checkout_lat" double precision,
    "checkout_lng" double precision,
    "checkout_accuracy_m" double precision,
    "checkout_distance_m" double precision,
    "checkout_mocked" boolean,
    "checkout_provider" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_records_checkout_pair_check" CHECK ((("checkout_at" IS NULL) = ("checkout_attempt_id" IS NULL)))
);


ALTER TABLE "public"."attendance_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_setup_progress" (
    "tenant_id" "uuid" NOT NULL,
    "current_step" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_setup_progress_step_check" CHECK (("current_step" = ANY (ARRAY['offices'::"text", 'timings'::"text", 'weekly_off'::"text", 'holidays'::"text", 'employees'::"text"])))
);


ALTER TABLE "public"."attendance_setup_progress" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_weekly_off_defaults" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "valid" "daterange" NOT NULL,
    "days" integer[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_weekly_off_defaults_days_has_working_day" CHECK (("cardinality"("days") < 7)),
    CONSTRAINT "attendance_weekly_off_defaults_days_range" CHECK (("days" <@ ARRAY[1, 2, 3, 4, 5, 6, 7])),
    CONSTRAINT "attendance_weekly_off_defaults_valid_not_empty" CHECK ((NOT "isempty"("valid")))
);


ALTER TABLE "public"."attendance_weekly_off_defaults" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_weekly_off_overrides" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "valid" "daterange" NOT NULL,
    "days" integer[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attendance_weekly_off_overrides_days_has_working_day" CHECK (("cardinality"("days") < 7)),
    CONSTRAINT "attendance_weekly_off_overrides_days_range" CHECK (("days" <@ ARRAY[1, 2, 3, 4, 5, 6, 7])),
    CONSTRAINT "attendance_weekly_off_overrides_valid_not_empty" CHECK ((NOT "isempty"("valid")))
);


ALTER TABLE "public"."attendance_weekly_off_overrides" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."country_codes" (
    "dial_code" "text" NOT NULL,
    "country_name" "text" NOT NULL,
    "iso2" character(2) NOT NULL
);


ALTER TABLE "public"."country_codes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "country_code" "text" NOT NULL,
    "phone_number" "text" NOT NULL,
    "address" "text",
    "city" "text",
    "created_via" "text" DEFAULT 'manual'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "formatted_address" "text",
    "pincode" "text",
    "latitude" double precision,
    "longitude" double precision,
    "place_id" "text",
    "address_details" character varying(255),
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "customers_created_via_check" CHECK (("created_via" = ANY (ARRAY['manual'::"text", 'job_creation'::"text"])))
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."early_access_signups" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" "text" NOT NULL,
    "phone" "text",
    "source" "text" DEFAULT 'web_home'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reference_code" "text" DEFAULT ('FZ-'::"text" || "upper"("substr"("replace"(("gen_random_uuid"())::"text", '-'::"text", ''::"text"), 1, 8))) NOT NULL,
    CONSTRAINT "early_access_signups_email_format" CHECK (((("char_length"("email") >= 3) AND ("char_length"("email") <= 254)) AND ("email" = "lower"("email")) AND ("email" ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'::"text"))),
    CONSTRAINT "early_access_signups_phone_e164" CHECK ((("phone" IS NULL) OR ("phone" ~ '^\+[1-9][0-9]{6,14}$'::"text"))),
    CONSTRAINT "early_access_signups_reference_code_format" CHECK (("reference_code" ~ '^FZ-[0-9A-F]{8}$'::"text")),
    CONSTRAINT "early_access_signups_source_length" CHECK ((("char_length"("source") >= 1) AND ("char_length"("source") <= 40)))
);


ALTER TABLE "public"."early_access_signups" OWNER TO "postgres";


COMMENT ON TABLE "public"."early_access_signups" IS 'Early access sign-ups (personal data). RLS on, no policies: service role only.';



CREATE TABLE IF NOT EXISTS "public"."employee_sequences" (
    "tenant_id" "uuid" NOT NULL,
    "last_seq" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."employee_sequences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."holidays" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "holiday_date" "date" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."holidays" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."idempotency_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "scope" "text" NOT NULL,
    "response_body" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."idempotency_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."job_sequences" (
    "tenant_id" "uuid" NOT NULL,
    "year" integer NOT NULL,
    "last_seq" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."job_sequences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."leave_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "leave_request_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "cause" "text" NOT NULL,
    "actor_id" "uuid",
    "reason" "text",
    "affected_dates" "date"[] DEFAULT '{}'::"date"[] NOT NULL,
    "seq" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "leave_events_cause_check" CHECK (("cause" = ANY (ARRAY['apply'::"text", 'apply_on_behalf'::"text", 'approve'::"text", 'reject'::"text", 'employee_cancel'::"text", 'owner_revoke'::"text", 'checkin_auto_cancel'::"text", 'disable'::"text", 'removal'::"text"])))
);


ALTER TABLE "public"."leave_events" OWNER TO "postgres";


ALTER TABLE "public"."leave_events" ALTER COLUMN "seq" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."leave_events_seq_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."leave_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "request_id" "uuid" NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "part" "text" NOT NULL,
    "reason" "text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "leave_requests_part_check" CHECK (("part" = ANY (ARRAY['full_day'::"text", 'first_half'::"text", 'second_half'::"text"]))),
    CONSTRAINT "leave_requests_reason_len_check" CHECK ((("char_length"("reason") >= 1) AND ("char_length"("reason") <= 500))),
    CONSTRAINT "leave_requests_span_check" CHECK (("end_date" >= "start_date"))
);


ALTER TABLE "public"."leave_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "job_id" "uuid",
    "event_type" "text" NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "read_at" timestamp with time zone,
    "pushed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "entity_type" "text",
    "entity_id" "uuid",
    "dedupe_key" "text",
    CONSTRAINT "notifications_entity_pair_chk" CHECK ((("entity_type" IS NULL) = ("entity_id" IS NULL)))
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."report_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "requested_by" "uuid" NOT NULL,
    "report_type" "text" NOT NULL,
    "params" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'queued'::"text" NOT NULL,
    "locked_until" timestamp with time zone,
    "attempt_count" integer DEFAULT 0 NOT NULL,
    "r2_key" "text",
    "file_size_bytes" bigint,
    "error_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "report_requests_params_check" CHECK (("jsonb_typeof"("params") = 'object'::"text")),
    CONSTRAINT "report_requests_status_check" CHECK (("status" = ANY (ARRAY['queued'::"text", 'generating'::"text", 'ready'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."report_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."skills" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "sort_order" integer NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "description" "text" NOT NULL,
    "icon" "text" NOT NULL,
    CONSTRAINT "skills_description_not_blank" CHECK (("length"("btrim"("description")) > 0)),
    CONSTRAINT "skills_icon_kebab_case" CHECK (("icon" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text"))
);


ALTER TABLE "public"."skills" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tenants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "company_name" "text" NOT NULL,
    "gstin" "text",
    "address" "text",
    "state_code" "text" NOT NULL,
    "upi_vpa" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "timezone" "text" DEFAULT 'Asia/Kolkata'::"text" NOT NULL,
    "weekly_off_configured_at" timestamp with time zone,
    CONSTRAINT "tenants_state_code_check" CHECK (("state_code" ~ '^[A-Z]{2}$'::"text"))
);


ALTER TABLE "public"."tenants" OWNER TO "postgres";


COMMENT ON COLUMN "public"."tenants"."weekly_off_configured_at" IS 'Set once, the first time the owner saves the everyone weekly-off rule (empty days included). Internal marker; the API exposes it as the boolean `configured`.';



CREATE TABLE IF NOT EXISTS "public"."user_skills" (
    "user_id" "uuid" NOT NULL,
    "skill_id" "uuid" NOT NULL
);


ALTER TABLE "public"."user_skills" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."workflow_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "skill_id" "uuid" NOT NULL,
    "version" integer NOT NULL,
    "steps" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "workflow_templates_steps_check" CHECK (("jsonb_typeof"("steps") = 'array'::"text")),
    CONSTRAINT "workflow_templates_steps_shape" CHECK ("public"."workflow_steps_valid"("steps"))
);


ALTER TABLE "public"."workflow_templates" OWNER TO "postgres";


ALTER TABLE ONLY "public"."activity_logs"
    ADD CONSTRAINT "activity_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_config"
    ADD CONSTRAINT "app_config_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."attachment_uploads"
    ADD CONSTRAINT "attachment_uploads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attachment_uploads"
    ADD CONSTRAINT "attachment_uploads_r2_key_key" UNIQUE ("r2_key");



ALTER TABLE ONLY "public"."attachments"
    ADD CONSTRAINT "attachments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attachments"
    ADD CONSTRAINT "attachments_r2_key_key" UNIQUE ("r2_key");



ALTER TABLE ONLY "public"."attendance_attempts"
    ADD CONSTRAINT "attendance_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_attempts"
    ADD CONSTRAINT "attendance_attempts_tenant_request_uq" UNIQUE ("tenant_id", "request_id");



ALTER TABLE ONLY "public"."attendance_corrections"
    ADD CONSTRAINT "attendance_corrections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_day_overrides"
    ADD CONSTRAINT "attendance_day_overrides_empdate_uq" UNIQUE ("employee_id", "work_date");



ALTER TABLE ONLY "public"."attendance_day_overrides"
    ADD CONSTRAINT "attendance_day_overrides_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_enrolments"
    ADD CONSTRAINT "attendance_enrolments_employee_valid_excl" EXCLUDE USING "gist" ("employee_id" WITH =, "valid" WITH &&);



ALTER TABLE ONLY "public"."attendance_enrolments"
    ADD CONSTRAINT "attendance_enrolments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_office_assignments"
    ADD CONSTRAINT "attendance_office_assignments_employee_valid_excl" EXCLUDE USING "gist" ("employee_id" WITH =, "valid" WITH &&);



ALTER TABLE ONLY "public"."attendance_office_assignments"
    ADD CONSTRAINT "attendance_office_assignments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_office_rules"
    ADD CONSTRAINT "attendance_office_rules_no_overlap" EXCLUDE USING "gist" ("office_id" WITH =, "valid" WITH &&);



ALTER TABLE ONLY "public"."attendance_office_rules"
    ADD CONSTRAINT "attendance_office_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_offices"
    ADD CONSTRAINT "attendance_offices_id_tenant_id_key" UNIQUE ("id", "tenant_id");



ALTER TABLE ONLY "public"."attendance_offices"
    ADD CONSTRAINT "attendance_offices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_onboarding"
    ADD CONSTRAINT "attendance_onboarding_pkey" PRIMARY KEY ("employee_id");



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_employee_work_date_uq" UNIQUE ("employee_id", "work_date");



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_settings"
    ADD CONSTRAINT "attendance_settings_pkey" PRIMARY KEY ("tenant_id");



ALTER TABLE ONLY "public"."attendance_setup_progress"
    ADD CONSTRAINT "attendance_setup_progress_pkey" PRIMARY KEY ("tenant_id");



ALTER TABLE ONLY "public"."attendance_weekly_off_defaults"
    ADD CONSTRAINT "attendance_weekly_off_defaults_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_weekly_off_defaults"
    ADD CONSTRAINT "attendance_weekly_off_defaults_tenant_valid_excl" EXCLUDE USING "gist" ("tenant_id" WITH =, "valid" WITH &&);



ALTER TABLE ONLY "public"."attendance_weekly_off_overrides"
    ADD CONSTRAINT "attendance_weekly_off_overrides_employee_valid_excl" EXCLUDE USING "gist" ("employee_id" WITH =, "valid" WITH &&);



ALTER TABLE ONLY "public"."attendance_weekly_off_overrides"
    ADD CONSTRAINT "attendance_weekly_off_overrides_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."country_codes"
    ADD CONSTRAINT "country_codes_iso2_key" UNIQUE ("iso2");



ALTER TABLE ONLY "public"."country_codes"
    ADD CONSTRAINT "country_codes_pkey" PRIMARY KEY ("dial_code");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."early_access_signups"
    ADD CONSTRAINT "early_access_signups_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."early_access_signups"
    ADD CONSTRAINT "early_access_signups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."early_access_signups"
    ADD CONSTRAINT "early_access_signups_reference_code_key" UNIQUE ("reference_code");



ALTER TABLE ONLY "public"."employee_sequences"
    ADD CONSTRAINT "employee_sequences_pkey" PRIMARY KEY ("tenant_id");



ALTER TABLE ONLY "public"."holidays"
    ADD CONSTRAINT "holidays_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."holidays"
    ADD CONSTRAINT "holidays_tenant_date_key" UNIQUE ("tenant_id", "holiday_date");



ALTER TABLE ONLY "public"."idempotency_log"
    ADD CONSTRAINT "idempotency_log_key_tenant_id_scope_key" UNIQUE ("key", "tenant_id", "scope");



ALTER TABLE ONLY "public"."idempotency_log"
    ADD CONSTRAINT "idempotency_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."job_sequences"
    ADD CONSTRAINT "job_sequences_pkey" PRIMARY KEY ("tenant_id", "year");



ALTER TABLE ONLY "public"."jobs"
    ADD CONSTRAINT "jobs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."leave_events"
    ADD CONSTRAINT "leave_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."leave_request_days"
    ADD CONSTRAINT "leave_request_days_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."leave_request_days"
    ADD CONSTRAINT "leave_request_days_request_date_uq" UNIQUE ("leave_request_id", "leave_date");



ALTER TABLE ONLY "public"."leave_requests"
    ADD CONSTRAINT "leave_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."leave_requests"
    ADD CONSTRAINT "leave_requests_tenant_request_uq" UNIQUE ("tenant_id", "request_id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."report_requests"
    ADD CONSTRAINT "report_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."report_requests"
    ADD CONSTRAINT "report_requests_r2_key_key" UNIQUE ("r2_key");



ALTER TABLE ONLY "public"."skills"
    ADD CONSTRAINT "skills_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tenants"
    ADD CONSTRAINT "tenants_owner_id_key" UNIQUE ("owner_id");



ALTER TABLE ONLY "public"."tenants"
    ADD CONSTRAINT "tenants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_skills"
    ADD CONSTRAINT "user_skills_pkey" PRIMARY KEY ("user_id", "skill_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_tenant_id_key" UNIQUE ("id", "tenant_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_tenant_employee_code_unique" UNIQUE ("tenant_id", "employee_code");



ALTER TABLE ONLY "public"."workflow_templates"
    ADD CONSTRAINT "workflow_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."workflow_templates"
    ADD CONSTRAINT "workflow_templates_skill_id_version_key" UNIQUE ("skill_id", "version");



CREATE INDEX "attendance_attempts_employee_time_idx" ON "public"."attendance_attempts" USING "btree" ("employee_id", "attempted_at" DESC);



CREATE INDEX "attendance_attempts_tenant_attempted_idx" ON "public"."attendance_attempts" USING "btree" ("tenant_id", "attempted_at");



CREATE INDEX "attendance_corrections_emp_date_seq_idx" ON "public"."attendance_corrections" USING "btree" ("employee_id", "work_date", "seq" DESC);



CREATE INDEX "attendance_corrections_owner_page_idx" ON "public"."attendance_corrections" USING "btree" ("tenant_id", "employee_id", "created_at" DESC, "id" DESC);



CREATE INDEX "attendance_office_assignments_office_id_idx" ON "public"."attendance_office_assignments" USING "btree" ("office_id");



CREATE UNIQUE INDEX "attendance_offices_tenant_name_unique" ON "public"."attendance_offices" USING "btree" ("tenant_id", "lower"("name"));



CREATE INDEX "attendance_records_checkin_attempt_idx" ON "public"."attendance_records" USING "btree" ("checkin_attempt_id");



CREATE INDEX "attendance_records_checkout_attempt_idx" ON "public"."attendance_records" USING "btree" ("checkout_attempt_id");



CREATE INDEX "attendance_records_tenant_work_date_idx" ON "public"."attendance_records" USING "btree" ("tenant_id", "work_date");



CREATE UNIQUE INDEX "customers_tenant_phone_unique" ON "public"."customers" USING "btree" ("tenant_id", "country_code", "phone_number");



CREATE INDEX "idx_activity_logs_job_id" ON "public"."activity_logs" USING "btree" ("job_id", "created_at");



CREATE INDEX "idx_attachment_uploads_job_id" ON "public"."attachment_uploads" USING "btree" ("job_id");



CREATE INDEX "idx_attachments_job_id" ON "public"."attachments" USING "btree" ("job_id");



CREATE INDEX "idx_jobs_customer_history" ON "public"."jobs" USING "btree" ("tenant_id", "customer_id", "scheduled_start" DESC, "id" DESC);



CREATE INDEX "idx_jobs_technician_id_updated_at" ON "public"."jobs" USING "btree" ("technician_id", "updated_at" DESC);



CREATE INDEX "idx_jobs_tenant_id_scheduled_start" ON "public"."jobs" USING "btree" ("tenant_id", "scheduled_start");



CREATE INDEX "idx_notifications_user_created_at" ON "public"."notifications" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_tenants_owner_id" ON "public"."tenants" USING "btree" ("owner_id");



CREATE INDEX "idx_users_tenant_id" ON "public"."users" USING "btree" ("tenant_id");



CREATE UNIQUE INDEX "jobs_tenant_job_number_unique" ON "public"."jobs" USING "btree" ("tenant_id", "job_number");



CREATE INDEX "leave_events_request_seq_idx" ON "public"."leave_events" USING "btree" ("leave_request_id", "seq" DESC);



CREATE UNIQUE INDEX "leave_request_days_active_uq" ON "public"."leave_request_days" USING "btree" ("employee_id", "leave_date") WHERE ("state" = ANY (ARRAY['pending'::"text", 'approved'::"text"]));



CREATE INDEX "leave_request_days_employee_date_idx" ON "public"."leave_request_days" USING "btree" ("employee_id", "leave_date");



CREATE INDEX "leave_request_days_request_idx" ON "public"."leave_request_days" USING "btree" ("leave_request_id");



CREATE INDEX "leave_request_days_tenant_pending_idx" ON "public"."leave_request_days" USING "btree" ("tenant_id") WHERE ("state" = 'pending'::"text");



CREATE INDEX "leave_requests_employee_created_idx" ON "public"."leave_requests" USING "btree" ("employee_id", "created_at" DESC);



CREATE INDEX "leave_requests_tenant_created_idx" ON "public"."leave_requests" USING "btree" ("tenant_id", "created_at" DESC);



CREATE UNIQUE INDEX "notifications_dedupe_key_uniq" ON "public"."notifications" USING "btree" ("dedupe_key") WHERE ("dedupe_key" IS NOT NULL);



CREATE INDEX "report_requests_generating_lease_idx" ON "public"."report_requests" USING "btree" ("locked_until") WHERE ("status" = 'generating'::"text");



CREATE INDEX "report_requests_queued_idx" ON "public"."report_requests" USING "btree" ("created_at") WHERE ("status" = 'queued'::"text");



CREATE INDEX "report_requests_tenant_created_idx" ON "public"."report_requests" USING "btree" ("tenant_id", "created_at" DESC);



CREATE UNIQUE INDEX "skills_name_unique" ON "public"."skills" USING "btree" ("lower"("name"));



CREATE UNIQUE INDEX "skills_sort_order_unique" ON "public"."skills" USING "btree" ("sort_order");



CREATE UNIQUE INDEX "uniq_attachments_signature_per_job" ON "public"."attachments" USING "btree" ("job_id") WHERE ("attachment_type" = 'signature'::"text");



CREATE UNIQUE INDEX "users_phone_no_tenant_unique" ON "public"."users" USING "btree" ("country_code", "phone_number") WHERE ("tenant_id" IS NULL);



CREATE UNIQUE INDEX "users_phone_per_tenant_unique" ON "public"."users" USING "btree" ("country_code", "phone_number", "tenant_id") WHERE ("tenant_id" IS NOT NULL);



CREATE OR REPLACE TRIGGER "app_config_updated_at" BEFORE UPDATE ON "public"."app_config" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE CONSTRAINT TRIGGER "attendance_assignment_coverage" AFTER INSERT OR DELETE OR UPDATE ON "public"."attendance_office_assignments" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "public"."attendance_enrolment_coverage_guard"();



CREATE OR REPLACE TRIGGER "attendance_day_overrides_updated_at" BEFORE UPDATE ON "public"."attendance_day_overrides" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE CONSTRAINT TRIGGER "attendance_enrolment_coverage" AFTER INSERT OR DELETE OR UPDATE ON "public"."attendance_enrolments" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "public"."attendance_enrolment_coverage_guard"();



CREATE OR REPLACE TRIGGER "attendance_office_rules_updated_at" BEFORE UPDATE ON "public"."attendance_office_rules" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "attendance_offices_updated_at" BEFORE UPDATE ON "public"."attendance_offices" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "attendance_settings_updated_at" BEFORE UPDATE ON "public"."attendance_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "attendance_setup_progress_updated_at" BEFORE UPDATE ON "public"."attendance_setup_progress" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "attendance_weekly_off_defaults_updated_at" BEFORE UPDATE ON "public"."attendance_weekly_off_defaults" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "attendance_weekly_off_overrides_updated_at" BEFORE UPDATE ON "public"."attendance_weekly_off_overrides" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "customers_updated_at" BEFORE UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "holidays_updated_at" BEFORE UPDATE ON "public"."holidays" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "leave_request_days_state_guard_trigger" BEFORE UPDATE OF "state" ON "public"."leave_request_days" FOR EACH ROW EXECUTE FUNCTION "public"."leave_request_days_state_guard"();



CREATE OR REPLACE TRIGGER "leave_request_days_updated_at" BEFORE UPDATE ON "public"."leave_request_days" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "leave_requests_updated_at" BEFORE UPDATE ON "public"."leave_requests" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "notifications_broadcast" AFTER INSERT ON "public"."notifications" FOR EACH ROW EXECUTE FUNCTION "public"."notifications_broadcast_changes"();



CREATE OR REPLACE TRIGGER "report_requests_in_flight_guard" BEFORE INSERT OR UPDATE OF "status" ON "public"."report_requests" FOR EACH ROW EXECUTE FUNCTION "public"."report_requests_in_flight_guard"();



CREATE OR REPLACE TRIGGER "report_requests_updated_at" BEFORE UPDATE ON "public"."report_requests" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "set_updated_at_attendance_attempts" BEFORE UPDATE ON "public"."attendance_attempts" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "set_updated_at_attendance_enrolments" BEFORE UPDATE ON "public"."attendance_enrolments" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "set_updated_at_attendance_office_assignments" BEFORE UPDATE ON "public"."attendance_office_assignments" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "set_updated_at_attendance_onboarding" BEFORE UPDATE ON "public"."attendance_onboarding" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "set_updated_at_attendance_records" BEFORE UPDATE ON "public"."attendance_records" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "tenants_timezone_guard" BEFORE INSERT OR UPDATE OF "timezone" ON "public"."tenants" FOR EACH ROW EXECUTE FUNCTION "public"."tenants_timezone_guard"();



CREATE OR REPLACE TRIGGER "trg_jobs_updated_at" BEFORE UPDATE ON "public"."jobs" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "users_set_employee_code" BEFORE INSERT OR UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."set_employee_code"();



ALTER TABLE ONLY "public"."activity_logs"
    ADD CONSTRAINT "activity_logs_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."activity_logs"
    ADD CONSTRAINT "activity_logs_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "public"."jobs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."activity_logs"
    ADD CONSTRAINT "activity_logs_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attachment_uploads"
    ADD CONSTRAINT "attachment_uploads_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "public"."jobs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attachment_uploads"
    ADD CONSTRAINT "attachment_uploads_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attachments"
    ADD CONSTRAINT "attachments_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "public"."jobs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attachments"
    ADD CONSTRAINT "attachments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attachments"
    ADD CONSTRAINT "attachments_upload_id_fkey" FOREIGN KEY ("upload_id") REFERENCES "public"."attachment_uploads"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."attendance_attempts"
    ADD CONSTRAINT "attendance_attempts_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_attempts"
    ADD CONSTRAINT "attendance_attempts_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_corrections"
    ADD CONSTRAINT "attendance_corrections_actor_tenant_fkey" FOREIGN KEY ("actor_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_corrections"
    ADD CONSTRAINT "attendance_corrections_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_corrections"
    ADD CONSTRAINT "attendance_corrections_override_fkey" FOREIGN KEY ("employee_id", "work_date") REFERENCES "public"."attendance_day_overrides"("employee_id", "work_date") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_corrections"
    ADD CONSTRAINT "attendance_corrections_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_day_overrides"
    ADD CONSTRAINT "attendance_day_overrides_created_by_tenant_fkey" FOREIGN KEY ("created_by", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_day_overrides"
    ADD CONSTRAINT "attendance_day_overrides_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_day_overrides"
    ADD CONSTRAINT "attendance_day_overrides_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_enrolments"
    ADD CONSTRAINT "attendance_enrolments_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_enrolments"
    ADD CONSTRAINT "attendance_enrolments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_office_assignments"
    ADD CONSTRAINT "attendance_office_assignments_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_office_assignments"
    ADD CONSTRAINT "attendance_office_assignments_office_tenant_fkey" FOREIGN KEY ("office_id", "tenant_id") REFERENCES "public"."attendance_offices"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_office_assignments"
    ADD CONSTRAINT "attendance_office_assignments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_office_rules"
    ADD CONSTRAINT "attendance_office_rules_office_id_fkey" FOREIGN KEY ("office_id") REFERENCES "public"."attendance_offices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_office_rules"
    ADD CONSTRAINT "attendance_office_rules_office_tenant_fkey" FOREIGN KEY ("office_id", "tenant_id") REFERENCES "public"."attendance_offices"("id", "tenant_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_office_rules"
    ADD CONSTRAINT "attendance_office_rules_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_offices"
    ADD CONSTRAINT "attendance_offices_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_onboarding"
    ADD CONSTRAINT "attendance_onboarding_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_onboarding"
    ADD CONSTRAINT "attendance_onboarding_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_checkin_attempt_fkey" FOREIGN KEY ("checkin_attempt_id") REFERENCES "public"."attendance_attempts"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_checkout_attempt_fkey" FOREIGN KEY ("checkout_attempt_id") REFERENCES "public"."attendance_attempts"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_office_rules_fkey" FOREIGN KEY ("office_rules_id") REFERENCES "public"."attendance_office_rules"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_office_tenant_fkey" FOREIGN KEY ("office_id", "tenant_id") REFERENCES "public"."attendance_offices"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_settings"
    ADD CONSTRAINT "attendance_settings_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_setup_progress"
    ADD CONSTRAINT "attendance_setup_progress_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_weekly_off_defaults"
    ADD CONSTRAINT "attendance_weekly_off_defaults_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_weekly_off_overrides"
    ADD CONSTRAINT "attendance_weekly_off_overrides_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."attendance_weekly_off_overrides"
    ADD CONSTRAINT "attendance_weekly_off_overrides_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_country_code_fkey" FOREIGN KEY ("country_code") REFERENCES "public"."country_codes"("dial_code");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employee_sequences"
    ADD CONSTRAINT "employee_sequences_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."holidays"
    ADD CONSTRAINT "holidays_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."idempotency_log"
    ADD CONSTRAINT "idempotency_log_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."job_sequences"
    ADD CONSTRAINT "job_sequences_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."jobs"
    ADD CONSTRAINT "jobs_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."jobs"
    ADD CONSTRAINT "jobs_skill_id_fkey" FOREIGN KEY ("skill_id") REFERENCES "public"."skills"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."jobs"
    ADD CONSTRAINT "jobs_technician_id_fkey" FOREIGN KEY ("technician_id") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."jobs"
    ADD CONSTRAINT "jobs_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."jobs"
    ADD CONSTRAINT "jobs_workflow_template_id_fkey" FOREIGN KEY ("workflow_template_id") REFERENCES "public"."workflow_templates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."leave_events"
    ADD CONSTRAINT "leave_events_actor_tenant_fkey" FOREIGN KEY ("actor_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."leave_events"
    ADD CONSTRAINT "leave_events_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."leave_events"
    ADD CONSTRAINT "leave_events_request_fkey" FOREIGN KEY ("leave_request_id") REFERENCES "public"."leave_requests"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."leave_events"
    ADD CONSTRAINT "leave_events_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."leave_request_days"
    ADD CONSTRAINT "leave_request_days_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."leave_request_days"
    ADD CONSTRAINT "leave_request_days_leave_request_id_fkey" FOREIGN KEY ("leave_request_id") REFERENCES "public"."leave_requests"("id");



ALTER TABLE ONLY "public"."leave_request_days"
    ADD CONSTRAINT "leave_request_days_request_fkey" FOREIGN KEY ("leave_request_id") REFERENCES "public"."leave_requests"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."leave_request_days"
    ADD CONSTRAINT "leave_request_days_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."leave_requests"
    ADD CONSTRAINT "leave_requests_created_by_tenant_fkey" FOREIGN KEY ("created_by", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."leave_requests"
    ADD CONSTRAINT "leave_requests_employee_tenant_fkey" FOREIGN KEY ("employee_id", "tenant_id") REFERENCES "public"."users"("id", "tenant_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."leave_requests"
    ADD CONSTRAINT "leave_requests_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "public"."jobs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."report_requests"
    ADD CONSTRAINT "report_requests_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."report_requests"
    ADD CONSTRAINT "report_requests_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tenants"
    ADD CONSTRAINT "tenants_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_skills"
    ADD CONSTRAINT "user_skills_skill_id_fkey" FOREIGN KEY ("skill_id") REFERENCES "public"."skills"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."user_skills"
    ADD CONSTRAINT "user_skills_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_country_code_fkey" FOREIGN KEY ("country_code") REFERENCES "public"."country_codes"("dial_code");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."workflow_templates"
    ADD CONSTRAINT "workflow_templates_skill_id_fkey" FOREIGN KEY ("skill_id") REFERENCES "public"."skills"("id") ON DELETE RESTRICT;



ALTER TABLE "public"."activity_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "activity_logs_tenant_isolation" ON "public"."activity_logs" USING (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid")) WITH CHECK (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid"));



ALTER TABLE "public"."app_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attachment_uploads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "attachment_uploads_tenant_isolation" ON "public"."attachment_uploads" USING (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid")) WITH CHECK (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid"));



ALTER TABLE "public"."attachments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "attachments_tenant_isolation" ON "public"."attachments" USING (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid")) WITH CHECK (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid"));



ALTER TABLE "public"."attendance_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_corrections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_day_overrides" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_enrolments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_office_assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_office_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_offices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_onboarding" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_setup_progress" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_weekly_off_defaults" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_weekly_off_overrides" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."country_codes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "country_codes_public_read" ON "public"."country_codes" FOR SELECT USING (true);



ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customers_tenant_isolation" ON "public"."customers" USING (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid")) WITH CHECK (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid"));



ALTER TABLE "public"."early_access_signups" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."employee_sequences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."holidays" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."idempotency_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "idempotency_log_tenant_isolation" ON "public"."idempotency_log" USING (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid")) WITH CHECK (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid"));



ALTER TABLE "public"."job_sequences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."jobs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "jobs_tenant_isolation" ON "public"."jobs" USING (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid")) WITH CHECK (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid"));



ALTER TABLE "public"."leave_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."leave_request_days" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."leave_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notifications_read_own" ON "public"."notifications" FOR SELECT USING ((("auth"."jwt"() ->> 'sub'::"text") = ("user_id")::"text"));



ALTER TABLE "public"."report_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "report_requests_tenant_isolation" ON "public"."report_requests" USING (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid")) WITH CHECK (("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid"));



ALTER TABLE "public"."skills" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "skills_authenticated_read" ON "public"."skills" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."tenants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tenants_read_own" ON "public"."tenants" FOR SELECT USING (("owner_id" = (("auth"."jwt"() ->> 'sub'::"text"))::"uuid"));



ALTER TABLE "public"."user_skills" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_skills_tenant_isolation" ON "public"."user_skills" USING ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE (("u"."id" = "user_skills"."user_id") AND ("u"."tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE (("u"."id" = "user_skills"."user_id") AND ("u"."tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid")))));



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_insert_only_service_role" ON "public"."users" FOR INSERT WITH CHECK (false);



CREATE POLICY "users_read_own_or_null_tenant" ON "public"."users" FOR SELECT USING (((("auth"."jwt"() ->> 'sub'::"text") = ("id")::"text") OR ("tenant_id" IS NULL) OR ("tenant_id" = (("auth"."jwt"() ->> 'tenantId'::"text"))::"uuid")));



CREATE POLICY "users_update_own" ON "public"."users" FOR UPDATE USING ((("auth"."jwt"() ->> 'sub'::"text") = ("id")::"text")) WITH CHECK ((("auth"."jwt"() ->> 'sub'::"text") = ("id")::"text"));



ALTER TABLE "public"."workflow_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "workflow_templates_authenticated_read" ON "public"."workflow_templates" FOR SELECT TO "authenticated" USING (true);





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."app_config";






SET SESSION AUTHORIZATION "postgres";
RESET SESSION AUTHORIZATION;



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";































































































































































































































































































































































































































































































































































































































































































































































GRANT ALL ON TABLE "public"."jobs" TO "anon";
GRANT ALL ON TABLE "public"."jobs" TO "authenticated";
GRANT ALL ON TABLE "public"."jobs" TO "service_role";



REVOKE ALL ON FUNCTION "public"."advance_workflow_step"("p_job_id" "uuid", "p_tenant_id" "uuid", "p_actor_id" "uuid", "p_step" "text", "p_new_status" "text", "p_expected_current_step" "text", "p_latitude" double precision, "p_longitude" double precision, "p_accuracy" double precision, "p_location_captured" boolean, "p_reason" "text", "p_accuracy_flagged" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."advance_workflow_step"("p_job_id" "uuid", "p_tenant_id" "uuid", "p_actor_id" "uuid", "p_step" "text", "p_new_status" "text", "p_expected_current_step" "text", "p_latitude" double precision, "p_longitude" double precision, "p_accuracy" double precision, "p_location_captured" boolean, "p_reason" "text", "p_accuracy_flagged" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_add_holiday"("p_tenant_id" "uuid", "p_holiday_date" "date", "p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_add_holiday"("p_tenant_id" "uuid", "p_holiday_date" "date", "p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_archive_office"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_office_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_archive_office"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_office_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_complete_setup"("p_tenant_id" "uuid", "p_actor_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_complete_setup"("p_tenant_id" "uuid", "p_actor_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_create_office"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_name" "text", "p_latitude" double precision, "p_longitude" double precision, "p_radius_m" integer, "p_start_time" time without time zone, "p_end_time" time without time zone, "p_late_cutoff_minutes" integer, "p_full_day_hours" numeric, "p_half_day_hours" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_create_office"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_name" "text", "p_latitude" double precision, "p_longitude" double precision, "p_radius_m" integer, "p_start_time" time without time zone, "p_end_time" time without time zone, "p_late_cutoff_minutes" integer, "p_full_day_hours" numeric, "p_half_day_hours" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_enrolment_coverage_guard"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_enrolment_coverage_guard"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_holiday_impact"("p_tenant_id" "uuid", "p_date" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_holiday_impact"("p_tenant_id" "uuid", "p_date" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_lock_employee"("p_employee_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_lock_employee"("p_employee_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_lock_tenant"("p_tenant_id" "uuid", "p_exclusive" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_lock_tenant"("p_tenant_id" "uuid", "p_exclusive" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_office_archive_blockers"("p_tenant_id" "uuid", "p_office_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_office_archive_blockers"("p_tenant_id" "uuid", "p_office_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_remove_holiday"("p_tenant_id" "uuid", "p_holiday_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_remove_holiday"("p_tenant_id" "uuid", "p_holiday_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_remove_weekly_off_override"("p_tenant_id" "uuid", "p_employee_id" "uuid", "p_effective_from" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_remove_weekly_off_override"("p_tenant_id" "uuid", "p_employee_id" "uuid", "p_effective_from" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_run_reminders"("p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_run_reminders"("p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_set_weekly_off_default"("p_tenant_id" "uuid", "p_days" integer[], "p_effective_from" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_set_weekly_off_default"("p_tenant_id" "uuid", "p_days" integer[], "p_effective_from" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_set_weekly_off_override"("p_tenant_id" "uuid", "p_employee_id" "uuid", "p_days" integer[], "p_effective_from" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_set_weekly_off_override"("p_tenant_id" "uuid", "p_employee_id" "uuid", "p_days" integer[], "p_effective_from" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_start_setup"("p_tenant_id" "uuid", "p_actor_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_start_setup"("p_tenant_id" "uuid", "p_actor_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_today"("p_tenant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_today"("p_tenant_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_update_holiday"("p_tenant_id" "uuid", "p_holiday_id" "uuid", "p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_update_holiday"("p_tenant_id" "uuid", "p_holiday_id" "uuid", "p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attendance_update_office_rules"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_office_id" "uuid", "p_start_time" time without time zone, "p_end_time" time without time zone, "p_late_cutoff_minutes" integer, "p_full_day_hours" numeric, "p_half_day_hours" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attendance_update_office_rules"("p_tenant_id" "uuid", "p_actor_id" "uuid", "p_office_id" "uuid", "p_start_time" time without time zone, "p_end_time" time without time zone, "p_late_cutoff_minutes" integer, "p_full_day_hours" numeric, "p_half_day_hours" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."confirm_attachment"("p_upload_id" "uuid", "p_job_id" "uuid", "p_tenant_id" "uuid", "p_size_bytes" integer, "p_actor_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."confirm_attachment"("p_upload_id" "uuid", "p_job_id" "uuid", "p_tenant_id" "uuid", "p_size_bytes" integer, "p_actor_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_job_with_log"("p_tenant_id" "uuid", "p_customer_id" "uuid", "p_technician_id" "uuid", "p_service_location" "text", "p_skill_id" "uuid", "p_scheduled_start" timestamp with time zone, "p_scheduled_end" timestamp with time zone, "p_description" "text", "p_priority" "text", "p_notes_for_technician" "text", "p_actor_id" "uuid", "p_year" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_job_with_log"("p_tenant_id" "uuid", "p_customer_id" "uuid", "p_technician_id" "uuid", "p_service_location" "text", "p_skill_id" "uuid", "p_scheduled_start" timestamp with time zone, "p_scheduled_end" timestamp with time zone, "p_description" "text", "p_priority" "text", "p_notes_for_technician" "text", "p_actor_id" "uuid", "p_year" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."increment_job_counter"("p_tenant_id" "uuid", "p_year" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."increment_job_counter"("p_tenant_id" "uuid", "p_year" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."leave_request_days_state_guard"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."leave_request_days_state_guard"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."notifications_broadcast_changes"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."notifications_broadcast_changes"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."report_requests_in_flight_guard"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."report_requests_in_flight_guard"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_employee_code"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_employee_code"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."setup_tenant_for_owner"("p_user_id" "uuid", "p_company_name" "text", "p_gstin" "text", "p_address" "text", "p_state_code" "text", "p_upi_vpa" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."setup_tenant_for_owner"("p_user_id" "uuid", "p_company_name" "text", "p_gstin" "text", "p_address" "text", "p_state_code" "text", "p_upi_vpa" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."tenants_timezone_guard"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."tenants_timezone_guard"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_job_with_log"("p_job_id" "uuid", "p_tenant_id" "uuid", "p_actor_id" "uuid", "p_cancel" boolean, "p_description" "text", "p_scheduled_start" timestamp with time zone, "p_scheduled_end" timestamp with time zone, "p_notes_for_technician" "text", "p_technician_id" "uuid", "p_priority" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_job_with_log"("p_job_id" "uuid", "p_tenant_id" "uuid", "p_actor_id" "uuid", "p_cancel" boolean, "p_description" "text", "p_scheduled_start" timestamp with time zone, "p_scheduled_end" timestamp with time zone, "p_notes_for_technician" "text", "p_technician_id" "uuid", "p_priority" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_updated_at_column"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."workflow_steps_valid"("p_steps" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."workflow_steps_valid"("p_steps" "jsonb") TO "service_role";
























GRANT ALL ON TABLE "public"."activity_logs" TO "anon";
GRANT ALL ON TABLE "public"."activity_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."activity_logs" TO "service_role";



GRANT ALL ON TABLE "public"."app_config" TO "anon";
GRANT ALL ON TABLE "public"."app_config" TO "authenticated";
GRANT ALL ON TABLE "public"."app_config" TO "service_role";



GRANT ALL ON TABLE "public"."attachment_uploads" TO "anon";
GRANT ALL ON TABLE "public"."attachment_uploads" TO "authenticated";
GRANT ALL ON TABLE "public"."attachment_uploads" TO "service_role";



GRANT ALL ON TABLE "public"."attachments" TO "anon";
GRANT ALL ON TABLE "public"."attachments" TO "authenticated";
GRANT ALL ON TABLE "public"."attachments" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_enrolments" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_office_assignments" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_offices" TO "anon";
GRANT ALL ON TABLE "public"."attendance_offices" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_offices" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_onboarding" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_settings" TO "anon";
GRANT ALL ON TABLE "public"."attendance_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_settings" TO "service_role";



GRANT ALL ON TABLE "public"."leave_request_days" TO "service_role";



GRANT SELECT,INSERT,DELETE,TRUNCATE,MAINTAIN ON TABLE "public"."users" TO "anon";
GRANT SELECT,INSERT,DELETE,TRUNCATE,MAINTAIN ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT UPDATE("name") ON TABLE "public"."users" TO "authenticated";



GRANT SELECT ON TABLE "public"."attendance_access_state" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_attempts" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_corrections" TO "service_role";



GRANT ALL ON SEQUENCE "public"."attendance_corrections_seq_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."attendance_corrections_seq_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."attendance_corrections_seq_seq" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_day_overrides" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_office_rules" TO "anon";
GRANT ALL ON TABLE "public"."attendance_office_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_office_rules" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_records" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_setup_progress" TO "anon";
GRANT ALL ON TABLE "public"."attendance_setup_progress" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_setup_progress" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_weekly_off_defaults" TO "anon";
GRANT ALL ON TABLE "public"."attendance_weekly_off_defaults" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_weekly_off_defaults" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_weekly_off_overrides" TO "anon";
GRANT ALL ON TABLE "public"."attendance_weekly_off_overrides" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_weekly_off_overrides" TO "service_role";



GRANT ALL ON TABLE "public"."country_codes" TO "anon";
GRANT ALL ON TABLE "public"."country_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."country_codes" TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON TABLE "public"."early_access_signups" TO "service_role";



GRANT ALL ON TABLE "public"."employee_sequences" TO "anon";
GRANT ALL ON TABLE "public"."employee_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."employee_sequences" TO "service_role";



GRANT ALL ON TABLE "public"."holidays" TO "anon";
GRANT ALL ON TABLE "public"."holidays" TO "authenticated";
GRANT ALL ON TABLE "public"."holidays" TO "service_role";



GRANT ALL ON TABLE "public"."idempotency_log" TO "anon";
GRANT ALL ON TABLE "public"."idempotency_log" TO "authenticated";
GRANT ALL ON TABLE "public"."idempotency_log" TO "service_role";



GRANT ALL ON TABLE "public"."job_sequences" TO "anon";
GRANT ALL ON TABLE "public"."job_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."job_sequences" TO "service_role";



GRANT ALL ON TABLE "public"."leave_events" TO "service_role";



GRANT ALL ON SEQUENCE "public"."leave_events_seq_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."leave_events_seq_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."leave_events_seq_seq" TO "service_role";



GRANT ALL ON TABLE "public"."leave_requests" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."report_requests" TO "anon";
GRANT ALL ON TABLE "public"."report_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."report_requests" TO "service_role";



GRANT ALL ON TABLE "public"."skills" TO "anon";
GRANT ALL ON TABLE "public"."skills" TO "authenticated";
GRANT ALL ON TABLE "public"."skills" TO "service_role";



GRANT ALL ON TABLE "public"."tenants" TO "anon";
GRANT ALL ON TABLE "public"."tenants" TO "authenticated";
GRANT ALL ON TABLE "public"."tenants" TO "service_role";



GRANT ALL ON TABLE "public"."user_skills" TO "anon";
GRANT ALL ON TABLE "public"."user_skills" TO "authenticated";
GRANT ALL ON TABLE "public"."user_skills" TO "service_role";



GRANT ALL ON TABLE "public"."workflow_templates" TO "anon";
GRANT ALL ON TABLE "public"."workflow_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."workflow_templates" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" REVOKE ALL ON FUNCTIONS FROM PUBLIC;




























