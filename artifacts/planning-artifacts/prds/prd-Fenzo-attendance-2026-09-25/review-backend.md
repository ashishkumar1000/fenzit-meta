# Backend Review — Attendance & Leave PRD (2026-09-25)

**Verdict: FEASIBLE WITH CHANGES — not ready for architecture hand-off.** The product scope can be built on the current fenzit-be stack. But the reuse plan carries two critical security gaps (giving technicians a realtime token, and copying an RPC that has no grant restrictions). It also misstates how tenant isolation is actually enforced, and it misses several tables and columns that the FRs depend on. Fix the critical and high items in the PRD/addendum before architecture starts.

Reviewed against: `fenzit-be` @ `6ccc278` (main), `project-context.md`, `_bmad-output/planning-artifacts/architecture.md`, `epics.md` (AR-1…AR-23). All paths below are relative to `workspace/core/backend/fenzit-be/` unless marked `fenzo-app:`.

**Counts:** Critical 2 · High 7 · Medium 9 · Low 8 (26 total)

---

## 0. Addendum claim verification (§A, §B1)

| Claim | Status | Evidence |
|---|---|---|
| A0: no distance validation on the backend; story 7-4 only checks range and flags accuracy > 100 m, never blocks | TRUE | `src/jobs/workflow.service.ts:196-216` ("Never hard-block … CAP-4") |
| A4: pg_cron already used (idempotency + notifications cleanup) | TRUE | `supabase/migrations/20260621000012_pg_cron_idempotency_cleanup.sql:4-24`, `20260909000004_notifications_cleanup.sql:13-24` |
| A4: reminders "idempotent via a unique key (recipient, type, date)" | FALSE as a reuse. `notifications` has no dedup column or unique index. It must be built (see H5) | `20260909000002_notifications_table.sql:21-34` |
| A6: `notifications` + realtime broadcast; `job_id` nullable | TRUE | `20260909000002…:54-71`, `20260920000008_notifications_job_id_nullable.sql:13` |
| A6: "Owner-only today: realtime token endpoint is owner-only" | TRUE. List/unread/mark-read are already role-agnostic (no `@Roles`) | `src/auth/auth.controller.ts:152-153`; `src/notifications/notifications.controller.ts:30-32` |
| A7: `pushed_at` is the push-outbox marker | TRUE | `20260909000002…:29` |
| A8: RPC + SECURITY DEFINER is the project standard | TRUE, but the standard is unsafe as copied (see C2). Only the report RPCs revoke EXECUTE | `20260913000002_advance_workflow_step_location_params.sql:16-34` (no REVOKE); `20260920000005_rpc_claim_report_request.sql:54-59` |
| A9: "**Global** idempotency interceptor + log table" | PARTIAL / WRONG. It is per-route (`@UseInterceptors`) and must be listed as a provider in each module. It is not global | `src/jobs/jobs.controller.ts:134,178`, `src/jobs/jobs.module.ts:18`, `src/app.module.ts:164-173` |
| A11: no tenant timezone field | TRUE | `20260619185741_create_tenants_and_rpc.sql:5-16` |
| B1: `JwtAuthGuard`, `RolesGuard`, `@Roles`, `@CurrentUser`, `RequestUser` reusable as-is | TRUE | `src/common/guards/*.ts`, `src/common/decorators/*.ts`, `src/common/interfaces/request-user.interface.ts` |
| B1: "`GlobalExceptionFilter`, `ErrorCode` enum, **PTxxx → HTTP mapping**" | PARTIAL. The filter does no PTxxx mapping. Each service maps `rpcError.code` itself. The filter does forward extra structured fields (useful for distance/radius) | `src/common/filters/global-exception.filter.ts:34-66,104-123`; `src/jobs/workflow.service.ts:239-250`; `src/jobs/jobs.service.ts:526-540`; `src/reports/reports.service.ts:48` |
| B1: `VALIDATION_PIPE_OPTIONS`, trim transformers, `PaginatedResponse`, cursor util | TRUE (`PaginatedResponse` also carries `hasMore`) | `src/common/validation-pipe-options.ts`, `src/common/utils/trim.transformer.ts`, `src/common/dto/paginated-response.dto.ts:1-11`, `src/common/utils/cursor.util.ts` |
| B1: `CursorScope` union can be extended | TRUE | `src/common/utils/cursor.util.ts:11-21` |
| B1: `hasInvalidCoordinates` reusable | TRUE, but it treats `undefined` as valid, so attendance must require lat/long/accuracy in the DTO | `src/common/utils/validate-coordinates.ts:9-17` |
| B1: `NotificationRow/Response.jobId` → nullable | TRUE that it is needed. It is also a **pre-existing bug**: report notifications already write `job_id: null`, but the types say `string` | `src/notifications/notifications.service.ts:24-31`, `dto/notification-response.dto.ts:12-13`, `src/reports/engine/report-notifications.ts:32-36` |
| B1: `GET /auth/realtime-token` → allow technicians (own topic only) | TRUE that the topic policy is already sub-scoped. **Security prerequisites are missing** (C1) | `20260909000002…:77-83`; `src/auth/auth.service.ts:212-226` |
| B1: `UsersService.listTechnicians` → shared method | PARTIAL. It is `private`, unpaginated, includes `invited` users, and lives in `UsersModule`, which depends on `JobsService`/`CustomersService` (M5) | `src/users/users.service.ts:190-194,363-398` |
| B1: `activity_logs` has `job_id NOT NULL` | TRUE | `20260621000002_create_jobs.sql:44` |
| B1: "existing IST util left alone for jobs" | TRUE, but IST is hard-coded in 7 places, not one (M2) | see M2 |
| B1: "Accuracy threshold (100 m) → shared constant" | CONFLICTS with the "Do not touch" list. The literal is inline in `workflow.service.ts` (L1) | `src/jobs/workflow.service.ts:214` |
| B1: RLS "owner: own tenant; technician: own rows" enforces isolation | MISLEADING. The API uses the service-role client almost everywhere, so RLS never runs on API paths (H3) | 14 files call `createAdmin()`; only `sync.service.ts:36` and `skills.service.ts:45` use a caller JWT |

---

## 1. Findings

### CRITICAL

#### C1. Technician realtime token becomes a working PostgREST credential. Combined with the default table grants and the `users_update_own` policy, this allows self-escalation of role or tenant
- **PRD location:** FR-27; addendum §A6, §B1 "Generalise: `GET /auth/realtime-token` → allow technicians".
- **Evidence:**
  - The realtime token is `{ sub, role: 'authenticated', exp }`, signed with `SUPABASE_JWT_SECRET` (`src/auth/auth.service.ts:212-226`). `authenticated` is a real Postgres role, so PostgREST accepts this token. `JwtAuthGuard` only blocks it on the Nest API (`src/common/guards/jwt-auth.guard.ts:32,80-85`), not on Supabase REST.
  - The app ships the Supabase URL and publishable key (`fenzo-app: src/config/index.ts:38-40`).
  - The repo's own notes say anon/authenticated **keep their default table grants** (`20260910000001_create_global_skills.sql:31-32`) and that older RPCs "still grant anon/authenticated EXECUTE" (`20260920000005_rpc_claim_report_request.sql:54-56`). No migration revokes table privileges.
  - `users_update_own` allows UPDATE of your own row with **no column restriction** (`20260619000001_create_users_table.sql:37-40`). RLS on `users` is on (`20260909000001…:18`). So a holder of this token can likely `PATCH /rest/v1/users?id=eq.<self>` with `{role:'owner'}` or `{tenant_id:'<other>'}`. The next OTP login then mints a JWT from that row (`auth.service.ts:182-186`). Every service trusts the JWT `tenantId` and uses the service role, so the result is a cross-tenant takeover.
  - `users_read_own_or_null_tenant` also exposes every user with `tenant_id IS NULL` (phone numbers of owners who haven't finished onboarding) to any authenticated token (`20260619000001…:23-29`).
  - Owners already hold these tokens today, so the hole exists now. FR-27 extends it to **every technician, tracked or not**.
- **Suggested fix:** Add a **prerequisite hardening story** to the PRD/addendum, which must merge before technicians get realtime tokens:
  1. `REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated`. Re-grant only what a direct client truly needs. Today that is nothing: Realtime Broadcast authorises through `realtime.messages`, not table grants. Keep `country_codes`/`skills` reads only if a direct client reads them.
  2. Drop `users_update_own`, or limit it to safe columns via a column-level GRANT.
  3. `REVOKE EXECUTE` on every existing public function from `public, anon, authenticated` (see C2).
  4. Verify live through the Supabase MCP. Extend `test/integration/rls-isolation.integration.spec.ts` (AR-20) with cases where a realtime-token holder tries a REST read/update and an RPC call; all must be denied.
  - Add an NFR: "A realtime token grants the Realtime socket only. It cannot read or write any table or call any function through PostgREST."
  - Call out that this is an **allowed grant-only change** to "do-not-touch" items (`advance_workflow_step`, report RPCs): no body changes.

#### C2. The reuse plan names `advance_workflow_step` as the RPC template. It is SECURITY DEFINER, takes the tenant and actor as caller-supplied parameters, and is still EXECUTE-able by anon/authenticated
- **PRD location:** Addendum §A8, §B1 "Reuse as-is: RPC pattern from `advance_workflow_step`"; §B1 "SECURITY DEFINER RPCs: check-in, check-out, leave …".
- **Evidence:** `20260913000002_advance_workflow_step_location_params.sql:16-34` (`p_tenant_id`, `p_actor_id` parameters, `SECURITY DEFINER`, no REVOKE). The only RPCs with a REVOKE are `claim_report_request` / `create_report_request` (`20260920000005…:57-59`, `20260920000006…:54-56`).
- **Impact:** If attendance RPCs copy this pattern, anyone holding a realtime token (C1) can call `/rest/v1/rpc/attendance_check_in` with any `p_tenant_id` / `p_employee_id` / coordinates. That means forged check-ins inside the radius, self-approved leave, and fake corrections. This breaks NFR-1/NFR-2 at the root.
- **Suggested fix:** In §B1, replace "RPC pattern from `advance_workflow_step`" with "RPC pattern from `claim_report_request` / `create_report_request`". Every attendance function must `REVOKE EXECUTE … FROM public, anon, authenticated` (service_role only). Tenant and actor IDs must come only from the verified JWT in the Nest service, never from a DTO. Also consider `SECURITY INVOKER`: the caller is already service_role, so DEFINER adds risk and no benefit. Add an AR-20 test that calls each new RPC with a realtime token and the publishable key and expects `permission denied`.

### HIGH

#### H1. A rejected check-in cannot both "reject" and "record the attempt" if the RPC raises. `RAISE` rolls back the attempt row and the 3rd-attempt notification
- **PRD location:** FR-7 (fake-GPS "every rejected attempt is recorded", 3rd-attempt Owner notification), FR-22, NFR-3; addendum §A3 ("the RPC rejects when `mocked = true` and logs the attempt"), §A8.
- **Evidence:** The project's convention is to reject by raising a PTxxx SQLSTATE and mapping it in the service (`advance_workflow_step…:52-64`, `workflow.service.ts:239-250`). PostgREST runs each RPC in one transaction, so a raise undoes every write in it.
- **Suggested fix:** State in the addendum that the check-in/out RPCs **return an outcome** (`accepted | outside_radius | low_accuracy | mock_location | already_checked_in | …` plus `distance_m`, `radius_m`, `accuracy_m`) and **commit** the attempt row (and the threshold notification) on reject paths. The Nest service turns the outcome into a 4xx with the right `ErrorCode`. Count fake-GPS attempts per distinct request key, so client retries of one tap don't reach "3 attempts".

#### H2. The idempotency interceptor does not give "repeated taps are safe". The key is optional, lookup-then-run is racy, results are stored after the response, and the scope ignores the user
- **PRD location:** FR-7 ("Repeated taps are safe … idempotent"), FR-8, FR-12, NFR-3; addendum §A9, §B1.
- **Evidence:** `src/common/interceptors/idempotency.interceptor.ts`
  - `:51-55`: no header means no dedup.
  - `:84-103`: read, then the handler runs, then `:108-131` a fire-and-forget `tap` insert. Two taps in flight both miss and both run.
  - `:106-107`: failures are not cached.
  - `:78`: scope is `METHOD:path` + tenant with **no user_id**. For a fixed path like `POST /attendance/check-in`, a same-tenant user who replays another user's key gets that user's cached body, coordinates included.
  - The architecture doc still describes an `IdempotencyGuard` that returns 200 on a hit (`architecture.md:1121-1131`). The code is an interceptor.
- **Suggested fix:**
  - Make the DB the idempotency authority. Store the client key on the row (`attendance_records.check_in_request_id UUID UNIQUE`, same for check-out and `leave_requests.client_request_id`). The RPC returns the existing row, not a 409, when the same key comes again.
  - Keep the interceptor as a fast path.
  - Make `X-Idempotency-Key` **required** on check-in/out and leave submit (422 if missing). Add `user_id` to the scope for attendance routes.
  - Correct A9 ("per-route interceptor, not global").
  - Say what a second *different* tap returns: `409 ALREADY_CHECKED_IN` with the existing record in the body, so the app can show success.

#### H3. NFR-1 relies on RLS, but the API bypasses RLS. Real isolation is service code plus RPC parameters, and the PRD never requires validating client-supplied employee IDs
- **PRD location:** NFR-1, FR-2 ("enforced server-side"), FR-16, FR-21, FR-26; addendum §B1 "RLS deny-by-default on every new table (owner: own tenant; technician: own rows)".
- **Evidence:**
  - 14 service files use `createAdmin()`. `users.service.ts:200`, `notifications.service.ts:55`, `idempotency.interceptor.ts:79`, and `20260909000001…:3-6` all state that the backend reads through the service role. RLS is "defense-in-depth" (`20260621000005_create_idempotency_log.sql:29-31`).
  - The architecture says the opposite (`architecture.md:377`: "RLS fires automatically. No explicit `WHERE tenant_id`"; AR-3), and AR-2 requires repositories that the code doesn't use.
  - Login JWTs can't reach PostgREST (role `owner`/`technician` isn't a PG role, `auth.service.ts:204-210`). Realtime tokens carry no `tenantId`. So policies written as `tenant_id = auth.jwt()->>'tenantId'` are never evaluated for anyone.
- **Suggested fix:** Reword NFR-1:
  - "Isolation is enforced in the service layer and inside every RPC. Tenant and actor come only from the verified JWT. Every target ID from a client (employee, office, leave request, holiday) is checked inside the RPC to belong to the caller's tenant (`users.role = 'technician'`, `tenant_id = p_tenant_id`, and for technicians `employee_id = p_actor_id`). New tables get RLS enabled with **no** policies for anon/authenticated (deny-all) plus REVOKE ALL, as a backstop."
  - Name the owner as `tenants.owner_id` (unique, `20260619185741…:7`) for "Owner" recipients.
  - Ask architecture to formally amend AR-2/AR-3/§2.6 to match the code, so the attendance module follows one stated rule.

#### H4. Office rules history is missing. FR-5 "changes apply forward only" conflicts with FR-10 recompute and §A5 "compute on read"
- **PRD location:** FR-5 ("Changes to timing and Hours rules apply from the date of the change. Past Day statuses are not recomputed"), FR-10 ("recomputes … including past dates"), FR-11, NFR-4; addendum §A5, §B1 tables.
- **Evidence:** §B1 lists `attendance_offices` but no rules version table. If Day status is computed on read (A5 option), editing Full-day hours from 8 to 9 silently rewrites every past month.
- **Suggested fix:** Choose one and write it in the addendum:
  - (a) an effective-dated `attendance_office_rules` (office_id, effective_from, start, end, cutoff, full_h, half_h, radius, lat/lng), or
  - (b) snapshot the rules used onto each `attendance_records` row at check-in (start, cutoff, full/half hours, office pin, radius) and read those.

  Also say that check-out is checked against the **check-in's** office and pin, even if the pin moved or the office was reassigned during the day (FR-6 already hints at this).

#### H5. The notifications generalisation is incomplete. There is no dedup key for reminders, the new entity columns must stay nullable or `advance_workflow_step` has to change, and the FR-23 uniqueness rule conflicts with itself
- **PRD location:** FR-22, FR-23 ("at most once per recipient per day per type"), FR-7 ("sent once per employee per month"), NFR-10; addendum §A4, §B1 Generalise row.
- **Evidence:**
  - `notifications` has no unique constraint beyond the PK and no dedup column (`20260909000002…:21-34`).
  - `advance_workflow_step` inserts `(tenant_id, user_id, job_id, event_type, payload)` only (`…location_params.sql:102-115`). New NOT NULL columns would break it. It is on the do-not-touch list.
  - Report notifications already use `job_id NULL` with the entity id inside `payload.reportId` (`report-notifications.ts:32-43`), which is a second pattern.
  - The job `event_type` is the raw workflow step key (`…:106`).
  - FR-23's owner summary is "once per **Office** per day", which breaks "once per recipient per day per type".
- **Suggested fix:**
  - Add `dedup_key TEXT NULL` with `UNIQUE (user_id, dedup_key) WHERE dedup_key IS NOT NULL`. All cron and threshold inserts use `ON CONFLICT DO NOTHING`, with keys like `checkin_reminder:<date>`, `owner_summary:<office_id>:<date>`, `fake_gps_threshold:<employee>:<yyyy-mm>`.
  - Make `entity_type` / `entity_id` nullable with `CHECK ((entity_type IS NULL) = (entity_id IS NULL))`. Say job rows keep `job_id` and are not backfilled. Decide whether report rows move to `entity_type='report'` (touches `report-notifications.ts`, which is allowed).
  - Namespace attendance event types (`attendance.*`, `leave.*`) and fix one payload key casing.
  - Reword FR-23 to "once per recipient per day per type **per scope (office)**".

#### H6. The §B1 "Build new" table list lacks tables that the FRs and NFRs need
- **PRD location:** FR-7 (attempt log, dashboard "Fake location attempt" flag), SM-C1 (rejection rate), NFR-6 ("all leave transitions recorded with actor, time and reason, never hard-deleted"), §A5 finalisation, FR-1 (wizard resume), FR-4 (onboarding once).
- **Evidence:** §B1 has `attendance_corrections` as the only audit table. `activity_logs` is job-only (`20260621000002_create_jobs.sql:44`). Notifications are pruned at 30/90 days (`20260909000004…:20-24`), so they cannot serve as history.
- **Suggested fix:** Add:
  - `attendance_check_attempts` (every rejected and accepted attempt: reason, distance, accuracy, mocked, provider, request key). This feeds FR-7 flags, the 3-attempt threshold, SM-C1 and NFR-9.
  - `leave_request_events` (append-only: from/to state, dates affected, actor, reason). No DELETE grant, and ideally a trigger that blocks UPDATE/DELETE.
  - `attendance_day_finalisations` (tenant_id, local_date, finalised_at) as the nightly-job watermark, so a missed cron tick catches up and a re-run is a no-op.
  - Wizard and onboarding state columns (`attendance_settings.setup_step/completed_at`, `attendance_enrolments.onboarded_at`).
  - Say whether owner config changes (radius, pin, holiday, weekly off, enrolment) are audited. A backend engineer would want this, because a radius change from 100 m to 1000 m is the easiest way to game SM-2.

#### H7. There is no rate limiting on check-in/out or leave, and the "you are X m away" response is a location oracle
- **PRD location:** FR-7/FR-8 (reject with exact distance), §7.2 (iOS has no mock signal), NFR-2. No rate-limit NFR exists.
- **Evidence:** No global throttler. The only limits are per-feature in-memory stores for OTP and Places (`src/places/places-rate-limit.store.ts:21-30`, `src/auth/auth.service.ts:67-82`). The cache is single-instance (AR-8).
- **Impact:** A spoofing client (iOS, or a patched Android app) can binary-search coordinates using the returned distance and then submit a "valid" check-in. Nothing slows or flags it.
- **Suggested fix:** Add an NFR:
  - Per-user limit on check-in/out attempts (for example 10/min and 30/day). Return 429 `RATE_LIMIT_EXCEEDED` with `retryAfterSeconds`; the filter already turns this into a `Retry-After` header (`global-exception.filter.ts:49-62,89-91`).
  - Per-user limit on leave submissions.
  - Log every rejected attempt (H6), and flag "many rejected attempts before a success" to the owner in the same way as fake GPS.
  - Consider rounding the distance in the message (for example to 10 m).

### MEDIUM

#### M1. The mock-location check is based on what the client says. "The server makes the decision" overstates it
- **PRD location:** FR-7 Fake GPS; addendum §A3.
- **Evidence:** The server can only read the `mocked`/`provider` fields that the client sends. Accuracy is also client-supplied (the same pattern as `advance-workflow.dto.ts` accuracy `@IsOptional @Min(0)`).
- **Fix:** In §7.2, say that the check is a deterrent for the unmodified app only. On Android builds, require `mocked` and `provider` (reject when missing, using a platform/app-version header). Treat a missing field from Android as flagged. Require `accuracy` (reject when missing).

#### M2. The timezone plan must cover all 7 IST hard-coded sites and amend the architecture rule. Day math should live in SQL
- **PRD location:** NFR-5; addendum §A11, §B1 ("timezone-aware day-range util (new)").
- **Evidence:**
  - IST is hard-coded in `src/common/utils/ist-day-range.util.ts:1`, `src/jobs/jobs.service.ts:206,366`, `src/reports/registry/report-params.util.ts:4`, `src/reports/registry/technician-job-activity.data.ts:76`, `src/reports/registry/technician-job-activity.template.ts:40`, `src/reports/templates/brand-kit/page-header.ts:124`.
  - Architecture rule: "IST conversion only at `date=today` query boundary" (`architecture.md:1155`).
- **Fix:**
  - Scope NFR-5 to attendance, and state that jobs and reports stay IST-only (a known limit for non-IST tenants).
  - Put the authority in SQL: one `tenant_local_date(p_tenant_id, ts)` / `tenant_local_now()` helper that uses `tenants.timezone`, used by every RPC and cron function. A TS util is needed only for display.
  - Validate `tenants.timezone` against `pg_timezone_names` with a trigger (a CHECK cannot use a subquery). Make it **not editable in v1**, because changing it re-reads history.
  - Expose it on `/users/me` → `tenant.timezone` for the app.
  - Amend architecture rule 1155.

#### M3. Server time and the midnight boundary are not specified precisely
- **PRD location:** FR-7 ("server timestamp"), FR-8, FR-10 step 7, FR-14 (revoke "before Office Start time"), NFR-2.
- **Fix:**
  - Say that timestamps and `work_date` come from DB `now()` inside the RPC, not Node `Date.now()`, so one clock decides both.
  - Add to FR-8: a check-out received after local midnight is rejected (`ATTENDANCE_DAY_CLOSED`) and the day becomes Checkout missing.
  - Say that the finalisation job and a late check-out are serialised (row lock on the attendance record).
  - The "before Start time" cut-off for revoke/cancel is evaluated against DB time in the tenant timezone.

#### M4. Error codes are not defined. The architecture requires every `error_code` in the enum
- **PRD location:** FR-7, FR-8, FR-12…FR-16, FR-5 (archive block), FR-18.
- **Evidence:** "Never invent `error_code` strings inline" (`architecture.md:1072`, AR-14). The current enum has no attendance codes (`src/common/enums/error-code.enum.ts:1-24`). The filter forwards extra fields (`global-exception.filter.ts:44-55`), so `distanceM`/`radiusM`/`officeName`/`accuracyM` can travel in the body.
- **Fix:** Add an error catalogue to the addendum, with each code's HTTP status and the PTxxx it maps from. For example: `ATTENDANCE_NOT_ENABLED` 403, `EMPLOYEE_NOT_TRACKED` 403, `OUTSIDE_OFFICE_RADIUS` 422 (+distanceM, radiusM, officeName), `LOCATION_ACCURACY_TOO_LOW` 422 (+accuracyM, maxAccuracyM), `MOCK_LOCATION_DETECTED` 422, `ALREADY_CHECKED_IN` 409, `NOT_CHECKED_IN` 409, `ALREADY_CHECKED_OUT` 409, `ATTENDANCE_DAY_CLOSED` 409, `LEAVE_OVERLAP` 409, `LEAVE_DATES_ALREADY_OFF` 422, `LEAVE_BACKDATE_LIMIT` 422, `LEAVE_DATE_HAS_CHECKIN` 409, `LEAVE_INVALID_TRANSITION` 409, `LEAVE_ALREADY_STARTED` 409, `OFFICE_HAS_EMPLOYEES` 409, `WEEKLY_OFF_NO_WORKING_DAY` 422. Also correct the §B1 claim that the filter maps PTxxx (see §0).

#### M5. There is no proper "owner lists technicians" API. Reusing `UsersService.listTechnicians` pulls the jobs module into attendance
- **PRD location:** FR-1 step 5, FR-2, FR-6, FR-24/25; addendum §B1 "`UsersService.listTechnicians` → shared method".
- **Evidence:**
  - Technicians are only listed inside the owner `/users/me` payload, together with jobs and customers (`src/users/users.service.ts:305-326`).
  - `listTechnicians` is private, has no pagination and no status filter, so it returns `invited` too (`:363-398`).
  - `UsersService` injects `JobsService` and `CustomersService` (`:190-194`), which goes against the spirit of NFR-12.
  - `users.status` is only `active | invited` (`20260619000001…:8`). There is no deactivated state, and no endpoint removes a technician.
- **Fix:** Build `GET /attendance/employees` in the attendance module. It queries `users` plus `attendance_enrolments` directly, is tenant-scoped and cursor-paginated (new `CursorScope`), and returns enrolment state and office. Say whether `invited` technicians can be enrolled (suggested: yes, but they receive no reminders until their first login). Drop the listTechnicians row from §B1.

#### M6. Leave state gaps and missing DB constraints
- **PRD location:** FR-9, FR-12, FR-13, FR-15, FR-16, FR-2, NFR-4.
- **Gaps:**
  - (a) Pending leave, then a check-in on that date, then owner approval. FR-9 only covers *approved* leave. Approval must skip or auto-cancel the days that have a check-in.
  - (b) Disabling an employee who has pending or future approved leave: are those days cancelled, and are notifications sent?
  - (c) Leave on dates before the enrolment effective date or after disable must be rejected.
  - (d) First-half and second-half on the same date through two requests: the overlap rule rejects this today. Is that intended?
  - (e) "7 days back" is not defined as calendar days in the tenant timezone.
  - (f) The overlap check needs a DB guarantee: a partial unique index on `leave_request_days (employee_id, leave_date) WHERE status IN ('pending','approved')` (with half-day rules), not only a service check.
- **Fix:** Add these consequences to the FRs and the constraint to NFR-4. State that the leave "split" is modelled as per-day status on `leave_request_days` (no new request rows).

#### M7. Correction precedence versus recompute is not defined
- **PRD location:** FR-21, FR-10 (Holiday add/remove recomputes past dates).
- **Fix:** Say whether an owner's direct Day-status override wins over later recomputes (for example a Holiday added over a corrected day). Suggested: an override is sticky and shown as "Corrected". The FR-20 holiday add warns the owner when it hits a corrected day.

#### M8. Effective-dated "exactly one" rules need a real DB mechanism
- **PRD location:** NFR-4 ("one Office per Tracked employee per date"), FR-2, FR-6, FR-18, FR-19.
- **Evidence:** The only extension enabled is `pg_cron`. There is no `btree_gist`, so there is no EXCLUDE constraint on date ranges (the only `CREATE EXTENSION` lines are in `20260621000012…:4` and `20260909000004…:13`).
- **Fix:** In the addendum, either enable `btree_gist` and use `EXCLUDE USING gist (employee_id WITH =, daterange(effective_from, effective_to) WITH &&)`, or use start-only rows (`UNIQUE (employee_id, effective_from)`, end derived). Require `effective_from >= tenant today` for weekly-off changes (FR-18 lets the owner "pick a date", which could rewrite history).

#### M9. NFR-9 observability cannot come from "existing telemetry". Coordinate retention is also undefined
- **PRD location:** NFR-9, NFR-11, SM-C1.
- **Evidence:** Telemetry only records the HTTP duration histogram by route/method/status (`src/telemetry/app-metrics.ts:8,19-29,50-64`). All rejection reasons share one 4xx. pg_cron runs inside Postgres, so Node OTel cannot see it.
- **Fix:**
  - Add new OTel counters (`attendance.check.rejected{reason}`, `attendance.check.accepted`).
  - Monitor cron through `cron.job_run_details` (for example a small Nest poller that emits `attendance.cron.failures`, or an alert on the finalisation watermark lagging, from H6).
  - Define a retention period for raw check-in coordinates and the attempt log (India DPDP Act 2023: purpose limitation). Owner views show distance, not raw lat/lng. Make NFR-9 "no coordinates in logs" a firm rule, not an `[ASSUMPTION]`.

### LOW

- **L1. The accuracy constant conflicts with "Do not touch".** Moving the 100 m literal into a shared constant edits `src/jobs/workflow.service.ts:214`. Either allow this behaviour-neutral edit explicitly, or give attendance its own constant. Also note that `dto.accuracy && …` treats 0 as missing there, so do not copy that check.
- **L2. §A9 wording.** "Global idempotency interceptor" should read "per-route `@UseInterceptors(IdempotencyInterceptor)` + module provider" (`jobs.module.ts:18`, `reports.module.ts:29`).
- **L3. Other mutations need idempotency too.** NFR-3 covers check-in/out and leave submit only. Approve, reject, revoke, cancel, on-behalf, correction and holiday add also need the interceptor plus compare-and-set, so an app retry gets the first result instead of a confusing 409.
- **L4. Login JWT never expires and cannot be revoked** (`src/app.module.ts:124-133`). The PRD should say that enrolment and enablement are checked in the DB on every attendance request (inside the RPC), never taken from the token or from cached `/users/me` flags.
- **L5. `/users/me` flags.** FR-3 needs a third flag, `attendanceHasHistory`, so a disabled employee can still open past records. Add `tenant.timezone` (M2). Compute "enrolled today" in the tenant timezone.
- **L6. Enabling mid-day.** FR-2 "effective date = today". An employee enabled at 14:00 becomes Absent tonight. Suggested rule: if enabled after the office Start time, today is Not tracked unless they check in.
- **L7. Distance computation.** There is no PostGIS/earthdistance. Specify haversine in plpgsql (metres, `double precision`, Earth radius 6,371,008.8 m) so the frontend `distanceUtils.ts` hint and the server agree to about 1 m. Reject when `distance > radius`, per FR-7.
- **L8. PRD housekeeping.** FR-27 appears after FR-23 and NFR-12 before NFR-11. Only FR-22 names recipients; FR-23 per-Office (see H5). `.memlog` "notifications job_id nullable" is fine, but the `NotificationRow.job_id: string` type bug fix should be listed in §B1 as a pre-existing fix, not as a new generalisation.

---

## 2. Required changes to "Do not touch" (the PRD would otherwise force a conflict)

| Item on do-not-touch list | Why it must be touched | Allowed change |
|---|---|---|
| `advance_workflow_step` | C2 / C1: EXECUTE must be revoked from anon/authenticated | Grant-only migration; no body change |
| Report claim/lease RPCs | Already revoked; nothing needed | none |
| `workflow.service.ts` | Only if the accuracy constant is shared (L1) | Optional; prefer a separate attendance constant |
| `notifications` insert in `advance_workflow_step` | New columns must not be NOT NULL (H5) | none, if the columns are nullable |
| `users` RLS policies (not listed, but shared) | C1: `users_update_own`, `users_read_own_or_null_tenant` | Security-hardening migration |

## 3. Suggested deploy order (per meta-repo rules)

1. **fenzit-be hardening** (C1/C2 grants and policies, AR-20 tests). This must go first and ship on its own.
2. **fenzit-be additive:** `tenants.timezone`, notifications `dedup_key`/`entity_*` (nullable), `NotificationRow.jobId` nullable, realtime-token opened to technicians, attendance tables/RPCs/cron, `/users/me` flags.
3. **fenzo-app:** technician bell, attendance module.

Every backend change here is additive, so no three-step breaking migration is needed.
