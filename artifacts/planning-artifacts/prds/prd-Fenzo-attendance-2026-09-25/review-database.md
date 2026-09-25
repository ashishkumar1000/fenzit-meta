# Database Review — Attendance & Leave PRD

**Verdict: NEEDS REVISION before architecture.** The direction (separate tables, compute in SQL, one shared notifications inbox, pg_cron for reminders) is sound. But there is 1 critical security gap in the RPC pattern the addendum says to copy, and 9 high gaps where the PRD/addendum has no clear data model for a stated requirement (corrections, leave split, office-rule history, reminder dedupe, rejected-attempt logging, cross-entity races).

- Reviewed: `prd.md`, `addendum.md` (§A, §B1), `.memlog.md`.
- Reviewed backend: `project-context.md`, migrations for users, tenants, notifications (+ broadcast trigger + `realtime.messages` policy), `notifications_job_id_nullable`, idempotency log, both pg_cron migrations, `advance_workflow_step` (all versions up to `20260913000002`), report request migrations (`20260920000004..07`), `IdempotencyInterceptor`, `NotificationsService`, `AuthService.mintRealtimeToken`, `ist-day-range.util.ts`, `test/integration/rls-isolation.integration.spec.ts`.
- Date: 2026-09-25. Read-only. Nothing was changed in the DB, PRD, addendum or migrations.

## Live DB check — what was and was not verified

Supabase MCP (`mcp__supabase__*`) was **not available** in this session (configured in `.mcp.json` but not loaded), and there is no Postgres connection string in `.env`. So:

| Checked live | How | Result |
|---|---|---|
| Exposed tables + RPCs | `GET /rest/v1/` OpenAPI (read-only, service key) | Tables: activity_logs, attachment_uploads, attachments, country_codes, customers, idempotency_log, job_sequences, jobs, notifications, report_requests, skills, tenants, user_skills, users, workflow_templates. RPCs: advance_workflow_step, confirm_attachment, create_job_with_log, increment_job_counter, setup_tenant_for_owner, update_job_with_log, workflow_steps_valid. **No attendance tables yet** (expected). |
| `tenants` columns | OpenAPI | id, owner_id, company_name, gstin, address, state_code, upi_vpa, created_at, updated_at. **No `timezone`** (matches addendum A11). |
| `notifications` columns | OpenAPI | id, tenant_id, user_id, job_id, event_type, payload, read_at, pushed_at, created_at. `job_id` is **not** in the required list, so it is nullable live (matches `20260920000008`). No `entity_type`/`entity_id`/dedupe column. |
| Does the anon/publishable key have EXECUTE on public functions? | `GET /rest/v1/rpc/workflow_steps_valid?p_steps=[]` with the anon key (an IMMUTABLE pure validator, no side effects) | **HTTP 200, returned `false`.** The anon role can execute public functions. No write function was called. |
| Anon read on `notifications` | `GET /rest/v1/notifications?limit=1` with anon key | `[]` (RLS works for tables). |

**Not verified live (needs Supabase MCP or SQL access):** `pg_policies` (incl. `realtime.messages`), `cron.job` contents, `pg_extension` (btree_gist / postgis / earthdistance), function grants (`pg_proc.proacl`). Findings on these rely on migration files. Migrations only ever `CREATE EXTENSION pg_cron`; no btree_gist, postgis or earthdistance is created anywhere.

---

## Findings

Severity counts: **critical 1, high 9, medium 9, low 7** (26 total).

### C1 — CRITICAL — The RPC pattern to "reuse" is callable by anyone with the app's publishable key

- **PRD location:** addendum §B1 "Reuse as-is: RPC pattern from `advance_workflow_step`"; §B1 "Build new: SECURITY DEFINER RPCs: check-in, check-out, leave apply/approve/…"; §B1 "Generalise: `GET /auth/realtime-token` → allow technicians"; NFR-1, NFR-2.
- **Evidence:**
  - `advance_workflow_step` (`20260913000002`) is `SECURITY DEFINER` and fully trusts `p_tenant_id` and `p_actor_id` from the caller. No migration revokes EXECUTE on it (grep: only `create_report_request` / `claim_report_request` had `REVOKE … FROM public, anon, authenticated`, and both were dropped in `20260920000007`).
  - Live: the anon key executes public functions (`workflow_steps_valid` → 200). `advance_workflow_step` is listed in the live PostgREST schema.
  - The publishable key is shipped in the mobile bundle: `fenzo-app/src/config/index.ts` (`SUPABASE_PUBLISHABLE_KEY`), used by `services/supabaseRealtime.ts`.
  - `mintRealtimeToken` issues `{ sub, role: 'authenticated' }` — a valid PostgREST JWT. Opening this endpoint to technicians gives every technician an `authenticated` token too.
- **Risk:** If attendance RPCs copy this pattern (`p_tenant_id`, `p_actor_id` params, default grants), anyone with the app bundle can call `POST /rest/v1/rpc/attendance_check_in` directly with any tenant/user id and any coordinates — skipping the Nest guards, the distance check inputs, and the mock flag. Same for `approve_leave`, `correct_attendance`. This breaks FR-7 trust, NFR-1 and NFR-2 completely. (The same hole exists today for the job RPCs — separate backlog item, not this PRD.)
- **Suggested PRD/addendum fix:** Add to NFR-1 / addendum §B1:
  - "Every attendance/leave SQL function is `SECURITY DEFINER SET search_path = public` (or `''`), and the migration runs `REVOKE EXECUTE … FROM public, anon, authenticated; GRANT EXECUTE … TO service_role;`. Add `ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM public, anon, authenticated`."
  - "Inside each function, re-check that `p_actor_id` belongs to `p_tenant_id` with the expected role (owner for approve/revoke/correct/on-behalf; enrolled technician for check-in/apply) — defence in depth."
  - "The RLS isolation test (AR-20) gets a probe: anon key and a technician realtime token calling each attendance RPC must fail with permission denied."
  - Change "Reuse as-is: RPC pattern from advance_workflow_step" to "Reuse the lock + PTxxx error pattern only; do NOT copy its grants."
  - Raise a separate backlog ticket to revoke EXECUTE on existing `advance_workflow_step`, `create_job_with_log`, `update_job_with_log`, `confirm_attachment`, `increment_job_counter`, `setup_tenant_for_owner`.

### H1 — HIGH — Addendum plans ~10 stored procedures, but the latest backend decision says "keep stored procedures to a minimum"

- **PRD location:** addendum §A8, §B1 ("SECURITY DEFINER RPCs … each writes state + audit + notification atomically", "Day status engine … SQL view/function", "pg_cron SQL functions").
- **Evidence:** `20260920000007_reports_drop_rpcs_in_flight_trigger.sql`: "User decision (2026-09-20): prefer plain SQL from the app — keep stored procedures to a minimum. Both report RPCs … are dropped." `project-context.md` still says atomic writes must use `supabase.rpc()`. supabase-js cannot open a multi-statement transaction.
- **Risk:** The dev agent will get two opposite rules. FR-22 ("notification in the same atomic operation") and NFR-3 cannot be met with plain `supabase.from()` calls; a trigger-based design (like the reports in-flight guard) hides logic.
- **Suggested fix:** Addendum should record an explicit exception: "Attendance & Leave is a multi-row, multi-table state machine with notifications; it uses SQL functions (not plain SQL) for every write, per project-context AR-10. The 2026-09-20 'minimum stored procedures' preference is consciously overridden here." List the exact function set (check_in, check_out, leave_apply, leave_decide, leave_cancel, leave_revoke, leave_on_behalf, correct_day, holiday_upsert/delete, enrol/disenrol, reminders_tick) so the scope of SQL is bounded.

### H2 — HIGH — "Record every rejected mock-location attempt" cannot work with the RAISE-to-reject pattern

- **PRD location:** FR-7 (mock attempts recorded; owner notified on 3rd attempt per month), NFR-9 (rejected check-ins logged), addendum §A3 ("RPC rejects when mocked = true and logs the attempt").
- **Evidence:** `advance_workflow_step` rejects with `RAISE EXCEPTION … USING ERRCODE = 'PT409'`. A RAISE rolls back the whole transaction, so any `INSERT INTO attendance_attempts` made before it is lost. The `IdempotencyInterceptor` also caches only successful responses, so every retry of a rejected attempt re-runs and counts again.
- **Risk:** Fake-GPS evidence and the 3rd-attempt owner notification silently never happen, or get double-counted on retries.
- **Suggested fix:** State in the addendum: "Check-in/out functions do not RAISE for business rejections (distance, accuracy, mocked). They insert an `attendance_attempts` row (user, tenant, office, kind = check_in/check_out, outcome = accepted/rejected_distance/rejected_accuracy/rejected_mocked, distance_m, accuracy_m, lat/lng, provider, client_request_id) and return a result row with `outcome`; Nest maps outcome → 422/409. RAISE is used only for true errors." For the monthly threshold: count rejected_mocked rows for (user, tenant-local month) inside the same call, and insert the owner notification with a dedupe key (see H8) so it fires once even under concurrency. Dedupe retries by `client_request_id` (unique per user).

### H3 — HIGH — "Office rule changes apply forward only" contradicts compute-on-read; office rules need history

- **PRD location:** FR-5 ("Changes to timing and Hours rules apply from the date of the change. Past Day statuses are not recomputed"), FR-10 (holiday/correction changes DO recompute past dates), addendum §A5 (materialise vs compute left open), §B1 (`attendance_offices` has no versioning).
- **Evidence:** No existing precedent; `attendance_offices` in §B1 is a single row per office.
- **Risk:** If day status is computed on read (the only simple way to meet FR-10 "recompute immediately"), then editing Full-day hours from 8 to 9 silently changes every past Present into Half day — breaking FR-5 and FR-11 ("totals match"). If statuses are materialised instead, every holiday/correction/leave change needs a recompute job, which is where bugs hide.
- **Suggested fix:** Addendum should decide: **compute on read**, and make rules effective-dated: `attendance_office_rules (office_id, effective_from DATE, effective_to DATE NULL, start_time TIME, end_time TIME, late_cutoff_min, full_day_hours NUMERIC(4,2), half_day_hours NUMERIC(4,2))` with a no-overlap exclusion constraint (H6). Also snapshot `late_minutes` and `office_id` on the attendance record at check-in (server authority, NFR-2). Then answer §A5: no nightly finalisation job is needed — Absent and Checkout missing are derived (`date < tenant_today AND …`).

### H4 — HIGH — Attendance corrections have no clear data model

- **PRD location:** FR-21 (set/change times or set Day status directly; never delete the original; employee sees note), UJ-4, NFR-6; addendum §B1 lists only `attendance_corrections (audit)`.
- **Evidence:** No such table exists; `activity_logs` is job-only (`job_id NOT NULL`) and immutable only by app convention (`20260621000002` comment).
- **Risk / gaps:** (a) A correction may target a date with **no** attendance record (Absent → Present), so corrections cannot hang off `attendance_record_id`. (b) "Never delete the original" + "set status directly" means there must be an override layer the day-status engine reads first — not stated. (c) Which statuses can be set directly? Can owner set "Leave" via correction (bypassing the leave flow and its notification)? (d) If check-in time is corrected, is `late_minutes` recomputed? (e) Multiple corrections on one day — latest wins?
- **Suggested fix:** Addendum model: `attendance_day_overrides (tenant_id, user_id, work_date, override_status NULL, check_in_at NULL, check_out_at NULL, note, corrected_by, corrected_at)` with `UNIQUE (tenant_id, user_id, work_date)` = current effective override; plus append-only `attendance_corrections` (one row per change: old JSON, new JSON, note NOT NULL CHECK length > 0, actor, at). PRD FR-21 should list allowed override statuses (suggest: Present, Half day, Absent only — never Leave/Holiday/Weekly off) and say "Late/Early flags are recomputed from corrected times".

### H5 — HIGH — Cross-entity races are not covered; only leave approve-vs-cancel is mentioned

- **PRD location:** NFR-3 ("concurrent Owner/Employee actions on the same leave"), FR-9 (check-in auto-cancels leave day), FR-12 ("past date with a check-in can't be requested"), FR-14/15 (today allowed only before Start time), FR-20 (holiday over approved leave).
- **Evidence:** `advance_workflow_step` shows the single-row `FOR UPDATE` pattern; reports use `pg_advisory_xact_lock(hashtextextended(tenant_id::text,0))`. Neither covers races across two tables.
- **Risk:** Under READ COMMITTED: (a) employee applies leave for today while a check-in for today commits → both pass their "no conflict" check. (b) Owner revokes today's leave at 09:59 while employee checks in at 09:59 → check-in auto-cancels a day that is also being revoked, two notifications with different stories. (c) Owner approves a leave while a holiday is added on one of its dates. FOR UPDATE on the leave row does not stop (a).
- **Suggested fix:** NFR-3 / addendum: "Every attendance/leave write function first takes `pg_advisory_xact_lock(hashtextextended('attendance:' || p_user_id, 0))` (per employee), then `FOR UPDATE` on the leave request row where relevant. Holiday add/remove takes a per-tenant attendance lock. The 'before Start time' check uses the DB clock `now()` inside the locked transaction." Back it with DB constraints (H7, M5) so the lock is not the only guard.

### H6 — HIGH — Effective-dated "no overlap" needs btree_gist, which is not enabled; nullable user_id breaks the weekly-off constraint

- **PRD location:** Glossary "Tracked employee … exactly one Office at any point", FR-2, FR-6, FR-18/19, NFR-4 ("one Office per Tracked employee per date"); addendum §B1 `attendance_enrolments (effective-dated)`, `weekly_off_rules (tenant + employee, effective-dated)`.
- **Evidence:** Migrations only create `pg_cron`. An `EXCLUDE USING gist (tenant_id WITH =, user_id WITH =, daterange(effective_from, effective_to, '[)') WITH &&)` needs `CREATE EXTENSION btree_gist`. Live extension list not verified (no SQL access).
- **Risk:** Without an exclusion constraint, two overlapping enrolments (e.g. reassignment + concurrent disable) give two offices on one date and double-counted days. For `weekly_off_rules` with `user_id NULL` meaning "tenant default", `NULL WITH =` never matches, so overlapping tenant defaults are not excluded.
- **Suggested fix:** Addendum: "Enable `btree_gist` (migration with `CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions`). Use `[effective_from, effective_to)` half-open `daterange`, `effective_to NULL` = open-ended. Exclusion constraints on enrolments, office rules (H3) and weekly-off rules. Split weekly offs into `tenant_weekly_off_rules` and `employee_weekly_off_overrides` (or two partial exclusion constraints `WHERE user_id IS NULL` / `IS NOT NULL`). 'Remove override' = close the range (`effective_to = date`), never delete." Store weekdays as `SMALLINT` bitmask or `SMALLINT[]` with CHECK (values 0–6; FR-18 "at least one working day" → mask <> 127).

### H7 — HIGH — "Split" of partial cancel/revoke is ambiguous; overlap rule has no DB constraint

- **PRD location:** FR-12 ("overlaps a Pending or Approved leave … rejected"), FR-14/15 ("the request is split"), FR-17, NFR-4 ("valid leave state transitions"); addendum §B1 `leave_requests + leave_request_days`.
- **Risk:** "Split" can mean creating a second request row or changing per-day state; the two give different history, notifications and FR-17 display ("Revoked (Thu–Fri)"). Without a per-day status and a partial unique index, the overlap rule is a check-then-insert race.
- **Suggested fix:** Addendum: "Do not create new requests on split. `leave_request_days (tenant_id, user_id, leave_request_id, leave_date, day_part CHECK IN ('full','first_half','second_half'), status CHECK IN ('pending','approved','rejected','cancelled','revoked','auto_cancelled_checkin','freed_by_holiday'), status_reason, changed_by, changed_at)`. `CREATE UNIQUE INDEX … ON leave_request_days (tenant_id, user_id, leave_date) WHERE status IN ('pending','approved')` enforces no overlap. Request-level status is derived (or kept with a 'partially_revoked' / 'partially_cancelled' value). Every transition inserts into append-only `leave_request_events`." Only Working days get day rows at submit time; PRD should confirm this (FR-12 says off days "don't count as leave").

### H8 — HIGH — Reminder "at most once per day per type" has no DB key on notifications

- **PRD location:** FR-23 ("at most once per recipient per day per type … no duplicates if the job re-runs"), FR-7 (3rd-attempt notification once per month), addendum §A4 ("Idempotent via a unique key (recipient, type, date)").
- **Evidence (live + migration):** `notifications` has only id, tenant_id, user_id, job_id, event_type, payload, read_at, pushed_at, created_at; the only index is `(user_id, created_at DESC)`; no unique constraint. A unique on `(user_id, event_type, created_at::date)` is wrong (UTC date, and `timestamptz::date` is not immutable so it can't be indexed). The owner summary is per Office, so (recipient, type, date) is not unique enough either.
- **Suggested fix:** Addendum: "Add `notifications.dedupe_key TEXT NULL` + `CREATE UNIQUE INDEX notifications_dedupe_uq ON notifications (user_id, dedupe_key) WHERE dedupe_key IS NOT NULL`. Reminder writers use `INSERT … ON CONFLICT DO NOTHING`. Keys: `checkin_reminder:{local_date}`, `checkout_reminder:{local_date}`, `owner_nci_summary:{office_id}:{local_date}`, `owner_pending_leave:{local_date}`, `fake_gps_threshold:{user_id}:{yyyy-mm}`." The broadcast trigger is AFTER INSERT, so a skipped conflict correctly sends nothing.

### H9 — HIGH — Tenant timezone: no validation, no change policy, and two date sources (TS util vs SQL)

- **PRD location:** Glossary "Tenant timezone", NFR-5, addendum §A11 and §B1 (`tenants.timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata'` + a new TS "timezone-aware day-range util").
- **Evidence:** Live `tenants` has no timezone column. Existing `ist-day-range.util.ts` hard-codes +05:30 in TypeScript.
- **Risk:** (a) An invalid IANA string makes every `AT TIME ZONE` call fail and stops the cron for all tenants in one loop. (b) If Nest computes "today" in TS and SQL computes it with `AT TIME ZONE`, they can disagree near midnight / on clock skew between app server and DB → check-in stored under one date, status engine reads another. (c) Changing the timezone later shifts the meaning of every stored `work_date`.
- **Suggested fix:** NFR-5 / addendum: "The attendance date key `work_date DATE` is computed only inside SQL as `(now() AT TIME ZONE t.timezone)::date` in the write function; the client and Nest never send or compute it. Validate `timezone` in a trigger/function against `pg_timezone_names` (CHECK can't use a subquery). v1: timezone is not editable once attendance is enabled (or: a change applies only to future dates and is audited)." Store all instants as `timestamptz`, office times as local `TIME`.

### M1 — MEDIUM — pg_cron design gaps: UTC scheduling, catch-up, window close, observability

- **PRD location:** FR-23, NFR-9 ("reminder job runs and failures … exposed as metrics (existing telemetry)"), addendum §A4/§A5 ("nightly job per Tenant timezone").
- **Evidence:** Existing jobs (`20260621000012`, `20260909000004`) are fixed UTC crons with inline SQL. pg_cron on Supabase runs in UTC and cannot schedule "per tenant timezone". Telemetry is OTLP from the Nest process (`6ccc278`), which pg_cron cannot reach.
- **Suggested fix:** Addendum: "One job `attendance-reminders-tick` every 1 or 5 min UTC calls `attendance_reminders_tick()`. For each tenant with attendance enabled it computes local now and inserts every reminder that is **due and not yet sent** for local today (dedupe key, H8) — so a missed tick catches up. A reminder is skipped if its condition is no longer true or the local day has ended (no 'haven't checked out' after midnight). No nightly finalisation job (H3). Reminder timing tolerance = tick interval (state it in FR-23). Function returns counts; runs are written to a small `attendance_job_runs` table that Nest reads to emit metrics (or accept `cron.job_run_details` only and drop the NFR-9 metric claim). Add cleanup of `cron.job_run_details`." Also use the unschedule-then-schedule idiom already in the repo.

### M2 — MEDIUM — Idempotency interceptor is best-effort; DB constraint is the real guard, and duplicate behaviour is not defined

- **PRD location:** FR-7 ("Repeated taps are safe … idempotent"), NFR-3, addendum §A9.
- **Evidence:** `IdempotencyInterceptor`: key is optional ("No key → proceed normally"), lookup-then-handler is not atomic (two concurrent same-key requests both run), lookup errors fail open, the log insert is fire-and-forget after the response, only success is cached, 24 h window.
- **Suggested fix:** NFR-3: "`UNIQUE (tenant_id, user_id, work_date)` on `attendance_records` is the source of truth. `X-Idempotency-Key` is **required** on check-in/out and leave submit routes (reject missing key with 422). A concurrent duplicate that loses the race returns 409 `ATTENDANCE_ALREADY_CHECKED_IN` with the existing record in the body, and the app treats it as success." For leave submit, the partial unique index in H7 is the guard.

### M3 — MEDIUM — Notifications generalisation needs constraints and a backfill

- **PRD location:** FR-22, FR-27, NFR-10, addendum §A6, §B1 ("add `entity_type` + `entity_id`").
- **Evidence:** Polymorphic `entity_id` can't have an FK. `job_id` is already nullable live, and report notifications (`report_ready|report_failed`) already use `job_id NULL` with the id only in payload. `NotificationRow.job_id: string` and `toResponse.jobId` in `notifications.service.ts` are typed non-null. `realtime.messages` policy is already sub-only (role-agnostic), so realtime for technicians needs only the token endpoint change — which feeds C1.
- **Suggested fix:** Addendum: "`entity_type TEXT NULL CHECK (entity_type IN ('job','report','leave_request','attendance_day','holiday'))`, `entity_id UUID NULL`, `CHECK ((entity_type IS NULL) = (entity_id IS NULL))`, `CHECK (entity_type <> 'job' OR job_id = entity_id)`. Backfill existing rows (`job` / `report`) in the same migration. Add `event_type` CHECK or registry table so push waves (NFR-10) have a stable list. Add partial index `(user_id) WHERE read_at IS NULL` for badge counts if volume grows." Note that realtime payload is the full row — never put coordinates in notification payloads.

### M4 — MEDIUM — RLS "technician: own rows" cannot use the JWT role claim; app bypasses RLS anyway

- **PRD location:** NFR-1, FR-26 ("enforced server-side"), FR-27, addendum §B1 ("RLS deny-by-default on every new table (owner: own tenant; technician: own rows)").
- **Evidence:** Every service uses `createAdmin()` (service role, bypasses RLS) — `NotificationsService`, `IdempotencyInterceptor`, etc. The login JWT's `role` is `owner|technician`, which is not a Postgres role, so PostgREST rejects it (RLS test comment: "must be 'authenticated'… app roles… rejected with 22023"). Realtime token has no `tenantId`.
- **Suggested fix:** NFR-1 should say: "Primary enforcement = Nest service layer (every query double-scoped by tenant_id and, for technicians, user_id — as NotificationsService does). RLS = deny-by-default defence in depth: owner policies via `EXISTS (SELECT 1 FROM tenants t WHERE t.id = tenant_id AND t.owner_id = (auth.jwt()->>'sub')::uuid)`; technician policies via `user_id = (auth.jwt()->>'sub')::uuid AND tenant_id = (auth.jwt()->>'tenantId')::uuid` (requires tenantId, so the realtime token reads nothing). No INSERT/UPDATE/DELETE policies at all (writes only through service-role functions)." Extend `rls-isolation.integration.spec.ts` with cross-tenant and cross-employee probes for every new table.

### M5 — MEDIUM — NFR-4 lists too few integrity constraints; tenant-crossing FKs are possible

- **PRD location:** NFR-4, FR-5, FR-6, FR-12, FR-14, FR-21.
- **Evidence:** `users` has no `UNIQUE (id, tenant_id)`, so a composite FK `(user_id, tenant_id) → users(id, tenant_id)` can't be declared today. Same technician phone can be a different `users` row per tenant (`20260620000003`). Owner is not trackable (§2.2) but nothing in the DB stops it.
- **Suggested fix:** Add to NFR-4 (or addendum constraint list):
  - Composite FKs so a child row can never point at another tenant's office/user: `UNIQUE (id, tenant_id)` on users and attendance_offices; FKs `(office_id, tenant_id)`, `(user_id, tenant_id)`.
  - Enrolment only for `role = 'technician' AND status = 'active'` (checked in the enrol function; role can't be an FK).
  - CHECKs: radius 50–1000; late_cutoff 0–120; `0 < half_day_hours < full_day_hours <= 24`; `end_time > start_time`; lat −90..90, lng −180..180, accuracy ≥ 0; `check_out_at > check_in_at`; leave reason `char_length BETWEEN 1 AND 500`; `day_part <> 'full'` ⇒ single date; revoke rows require a reason; correction note NOT NULL non-empty; `UNIQUE (tenant_id, holiday_date)`; `UNIQUE (tenant_id, lower(name))` for offices (optional).
  - FKs to users `ON DELETE RESTRICT` (audit must survive).
  - The 7-day back-date limit and "before Start time" rules use `now()` so they must live in the functions, not CHECKs — say so.

### M6 — MEDIUM — Several state interactions have no rule

- **PRD location:** FR-9, FR-12, FR-13, FR-19, FR-20, FR-21.
- **Gaps:** (a) Pending leave for date D, employee checks in on D, then owner approves → approved leave on a day with a check-in (FR-9 covers only Approved). (b) Owner correction adds a check-in on an Approved-leave date — auto-cancel the leave day? notify? (c) A weekly-off override made after a leave was approved turns a leave date into a weekly off — is the leave day freed like FR-20 holidays? (d) Removing a past Holiday with no check-in turns the day into Absent retroactively — FR-20 warns only for leave overlap. (e) Holiday added on a date inside a **Pending** leave.
- **Suggested fix:** Add one line each to the FRs. Suggested defaults: (a) approve skips dates with a check-in (marks them `auto_cancelled_checkin`); (b) same as FR-9; (c) same as FR-20 (freed + notify); (d) owner warned with count of affected employees; (e) day freed, request stays pending for the rest.

### M7 — MEDIUM — Audit "never hard-deleted" is not enforced by the DB

- **PRD location:** NFR-6, FR-21.
- **Evidence:** `activity_logs` immutability is "app-enforced in Phase 1" (`20260621000002`). All tenant FKs use `ON DELETE CASCADE` (jobs, report_requests, idempotency_log), so deleting a tenant wipes audit.
- **Suggested fix:** NFR-6: "`attendance_corrections`, `leave_request_events`, `attendance_attempts` are append-only: a BEFORE UPDATE OR DELETE trigger raises (except for a documented tenant-offboarding path). Tenant FK on audit tables is `ON DELETE RESTRICT`, or the PRD accepts that tenant deletion removes all attendance data (state which)."

### M8 — MEDIUM — No retention rule for raw coordinates and fake-GPS attempts

- **PRD location:** NFR-9, NFR-11, FR-7 ("Every rejected mock-location attempt is recorded (…coordinates…)").
- **Risk:** Precise employee locations stored forever, per check-in and per rejected attempt, with no stated purpose limit (India DPDP Act 2023 expects purpose + retention).
- **Suggested fix:** Add to NFR-11: "Keep lat/lng on accepted records for N months (e.g. 13), then null them via pg_cron, keeping distance_m and accuracy_m. Rejected attempts: keep 90 days. Attendance status data (dates, times, flags) kept indefinitely." Confirm N with the owner.

### M9 — MEDIUM — Monthly grid read path and indexes are not defined

- **PRD location:** FR-24, FR-25, FR-26, FR-11, NFR-7 (50 employees ≤ 3 s p95), addendum §B1 ("Day status engine + monthly summary queries (SQL view/function)").
- **Risk:** The grid needs enrolments × dates × (office rules, weekly offs, holidays, leave days, records, overrides, attempts). Doing it in TS with many PostgREST calls will be slow; doing it in SQL conflicts with H1 unless agreed. FR-11 "totals match exactly" needs a single engine for owner and employee views.
- **Suggested fix:** Addendum: "One STABLE SQL function `attendance_day_statuses(p_tenant_id, p_from, p_to, p_user_id NULL)` returns one row per (user, date) and is the only status engine; owner grid, employee view, dashboard and summaries all read from it. Indexes: `attendance_records (tenant_id, work_date, user_id)` (the unique index covers it if ordered so), `leave_request_days (tenant_id, leave_date) WHERE status IN ('pending','approved')`, `holidays UNIQUE (tenant_id, holiday_date)`, enrolments `(tenant_id, user_id)`, `attendance_attempts (tenant_id, user_id, created_at) WHERE outcome = 'rejected_mocked'`, `attendance_records (tenant_id, work_date) WHERE check_out_at IS NULL` for the Checkout-missing dashboard flag." Grant it to service_role only (C1).

### L1 — LOW — Notifications cleanup deleting attendance notifications is acceptable, but say so

- **PRD location:** FR-22, FR-23, NFR-10.
- **Evidence:** `20260909000004` deletes rows older than 30 days where `pushed_at IS NOT NULL`, or older than 90 days. Today nothing sets `pushed_at`, so all rows live 90 days; after push lands, pushed rows die at 30 days while wave-2 (never pushed) rows live 90 days.
- **Assessment:** OK — as long as notifications are never the record of truth. Leave history, corrections and fake-GPS flags must come from attendance tables (H2, H4, H7). The dedupe keys (H8) only need to live for the current day/month, which is inside the window.
- **Suggested fix:** Add to FR-22: "Notifications are a 30–90 day inbox, not a record. All history shown in FR-17/FR-25/FR-26 comes from attendance/leave tables." Tapping an old deep link whose notification is gone is fine; tapping a notification whose leave was later changed must show the current state.

### L2 — LOW — Distance calc: plain haversine in SQL is enough

- **PRD location:** FR-7, addendum §A0.
- **Evidence:** No PostGIS / earthdistance / cube in any migration (live extension list not verified).
- **Suggested fix:** Addendum: "IMMUTABLE SQL function `haversine_m(lat1, lng1, lat2, lng2) → double precision` (earth radius 6 371 008.8 m). Error at ≤ 1 km is well under 1 m — no PostGIS needed. Store office and attempt coordinates as `double precision`. Compare `distance_m > radius_m` (state whether accuracy is used, e.g. no benefit-of-doubt in v1)." Return integer metres in the error payload.

### L3 — LOW — Weekly-off effective date can be picked in the past

- **PRD location:** FR-18 ("effective from a date the Owner picks (default today). Dates before it are unchanged"), FR-10.
- **Risk:** Picking last week as the effective date rewrites history, which FR-18 intends to avoid. Also unclear whether "no weekly off" (empty set) is allowed.
- **Suggested fix:** "Effective date must be ≥ tenant today." Say whether an empty weekly-off set is allowed.

### L4 — LOW — Wizard resume and module-level state need columns

- **PRD location:** FR-1 (resume, "until completed no employee sees UI"), FR-3, addendum §B1 `attendance_settings`.
- **Suggested fix:** `attendance_settings (tenant_id PK/FK, wizard_step SMALLINT, completed_at TIMESTAMPTZ NULL, enabled BOOLEAN)`. Enrolments are created with effective_from = tenant today only when the wizard completes (single function). State whether the owner can switch the whole module off later (not in PRD) and what the cron does then.

### L5 — LOW — Disable/reassign boundary for "today" is unclear

- **PRD location:** FR-2 ("Dates after disabling show as Not tracked"), FR-6 (reassign after today's check-in → tomorrow).
- **Suggested fix:** "Disable closes the enrolment at `effective_to = tenant today + 1` (today stays tracked) if the employee has checked in today, else at today." Same rule as FR-6, one sentence.

### L6 — LOW — Office archive vs assign race, and future-dated enrolments

- **PRD location:** FR-5 ("can't be archived until they are reassigned").
- **Suggested fix:** "Archive checks for current **and future** enrolments under a lock on the office row; `archived_at TIMESTAMPTZ`, never delete an office (FKs from records)."

### L7 — LOW — Holiday edits/removals are not audited

- **PRD location:** FR-20 (past holidays can be added/removed, statuses recomputed), NFR-6 (audit covers corrections and leave only).
- **Risk:** Removing a past holiday changes past Day statuses and Days worked with no trail — the kind of dispute §1 wants to end.
- **Suggested fix:** Soft-delete holidays (`removed_at`, `removed_by`) and add holiday changes to NFR-6's audited list.

---

## Suggested addendum table sketch (for the architect, not a requirement)

| Table | Key constraints |
|---|---|
| `tenants.timezone` | NOT NULL DEFAULT 'Asia/Kolkata', validated vs `pg_timezone_names` |
| `attendance_settings` | PK tenant_id; wizard_step, completed_at |
| `attendance_offices` | UNIQUE (id, tenant_id); lat/lng CHECK; radius 50–1000; archived_at |
| `attendance_office_rules` | effective-dated, EXCLUDE gist per office; time/hours CHECKs |
| `attendance_enrolments` | composite FKs; EXCLUDE gist per (tenant, user) |
| `tenant_weekly_off_rules`, `employee_weekly_off_overrides` | EXCLUDE gist; bitmask CHECK |
| `holidays` | UNIQUE (tenant_id, holiday_date) among non-removed; soft delete |
| `attendance_records` | UNIQUE (tenant_id, user_id, work_date); office_id + late_minutes snapshot |
| `attendance_attempts` | append-only; outcome CHECK; client_request_id UNIQUE per user |
| `attendance_day_overrides` + `attendance_corrections` | UNIQUE per (tenant, user, date); corrections append-only |
| `leave_requests`, `leave_request_days`, `leave_request_events` | partial UNIQUE on active day; per-day status; events append-only |
| `notifications` (+ `entity_type`, `entity_id`, `dedupe_key`) | pair CHECK; partial UNIQUE (user_id, dedupe_key) |

All write functions: SECURITY DEFINER, fixed search_path, per-employee advisory lock, EXECUTE revoked from public/anon/authenticated (C1).

## Deploy order note

All of this is additive in `fenzit-be` (new tables, new nullable columns on `notifications`, new `tenants.timezone` with default) → merge/deploy `fenzit-be` first, then `fenzo-app`. The `NotificationResponse.jobId` → nullable change is already true in the DB; the DTO change is additive for the app as long as it already handles `null`. The C1 revoke on the existing job RPCs is a separate backend-only change (Nest calls them with the service role, so it is non-breaking for the app).
