---
title: 'Attendance module foundation — timezone, settings, setup gating & setup routes'
type: 'feature'
created: '2026-09-26'
status: 'done'
review_loop_iteration: 1
baseline_commit: 'ee44907'
context:
  - '{project-root}/artifacts/planning-artifacts/epics-attendance-leave.md'
  - '{project-root}/artifacts/planning-artifacts/architecture/architecture-attendance-leave-2026-09-25/ARCHITECTURE-SPINE.md'
  - '{project-root}/artifacts/implementation-artifacts/epic-14-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The attendance & leave module has no foundation — no `tenants.timezone` (all "today" maths is hard-coded IST offsets across services), no per-tenant settings/kill switch, no wizard-progress persistence for the FR-1 setup wizard, and none of the AD-5 advisory-lock helpers later attendance RPCs serialise through.

**Approach:** One migration adds `tenants.timezone` (TEXT NOT NULL DEFAULT 'Asia/Kolkata') validated by a trigger against `pg_timezone_names` (PT422, not a CHECK — Postgres can't validate timezone names in a CHECK); a second creates `attendance_settings` (per-tenant `enabled` kill switch + `setup_completed_at`) and `attendance_setup_progress` (current wizard step); a third creates the shared helpers `attendance_today(p_tenant_id)`, `attendance_lock_tenant(p_tenant_id, p_exclusive)`, `attendance_lock_employee(p_employee_id)` (AD-5/AD-7) and the `attendance_complete_setup` RPC. Every function is `SECURITY DEFINER SET search_path = public` with EXECUTE revoked from `PUBLIC, anon, authenticated` (AD-3, the sanctioned stored-procedure exception). A small `src/attendance/` NestJS module exposes `/attendance/setup` routes (resume / start / save step / complete) — step saves are guarded admin-client upserts (AD-3 single-row exception), completion goes through the RPC.

**Scope decisions locked with the user (2026-09-26):**
- `attendance_complete_setup` ships in this story as PL/pgSQL even though it gates on the offices table (15-3) and enrolments/assignments (15-7) that don't exist yet — PL/pgSQL bodies are not validated at CREATE time, so the migration applies cleanly; the function only becomes callable once 15-3/15-7 land, and its real-DB gating probes move to 15-7.
- The NestJS `/attendance/setup` routes are in scope here (no later story covers them).
- Migrations are date-prefixed from `20260926000001`.
- `attendance_settings` rows are created on demand (upsert when the wizard starts) — no backfill for existing tenants.

**Deviations during implementation (2026-09-26, all within intent):**
- A 4th migration `20260926000004_rpc_attendance_start_setup.sql` adds `attendance_start_setup(p_tenant_id, p_actor_id)`: starting the wizard writes TWO row-sets (settings + progress), and AD-3 says multi-row-set writes are exactly one RPC — the single-table exception covers only the PATCH step marker. Idempotent by construction (`on conflict do nothing` both rows — a restart never resets progress); no tenant lock (nothing to serialise; a concurrent complete interleaving is still a valid state).
- The two new tables shipped with the repo's tenant-isolation policy (FOR ALL keyed on the JWT `tenantId` claim, mirroring `report_requests` 20260920000004). **Superseded by the BMAD review decision (2026-09-26): the policies are DROPPED — deny-by-default, admin-client-only** (migration 2 amended in-file; the live DB got the corrective drop + helper rewrites via MCP `fix_15_2_review_deny_by_default_and_fail_loud_helpers`). These tables hold module state (`enabled`, `setup_completed_at`), so a tenant JWT must not be able to self-enable or fake completion through PostgREST.
- `saveStep` ships a **guarded UPDATE, not the frozen "guarded admin-client upsert"** — the frozen I/O matrix demands "not started → 404", which a true upsert could never produce; the UPDATE returning zero rows is the unambiguous resolution (recorded after review; `docs/api-contracts.md` already described it correctly).
- `attendance_today` and `attendance_lock_tenant` fail loud (review fixes): unknown tenant → `PT404`/`ATTENDANCE_TENANT_NOT_FOUND` (no silent NULL "today"); `p_exclusive = NULL` → `PT400`/`VALIDATION_ERROR` (no silent shared lock).
- This database exposes the shared advisory lock as a distinct `pg_advisory_xact_lock_shared(bigint)` — there is NO `pg_advisory_xact_lock(bigint, boolean)` overload (verified live, 42883); `attendance_lock_tenant` branches on `p_exclusive` accordingly, matching AD-5's `pg_advisory_xact_lock[_shared]` wording.
- Unit tests must run under Node (`~/.nvm/versions/node/v24.13.0/bin` on PATH), not bun — jest via bun 1.3.14 dies in jest-runtime (`getMockedModuleClass: Attempted to assign to readonly property`) on all 52 suites; under Node 24.13.0 the full suite is green.

## Boundaries & Constraints

**Always:**
- Migration files live in `fenzit-be/supabase/migrations/` AND are applied via Supabase MCP (start: `20260926000001`; latest applied today is `20260925000006`).
- Every attendance function in the same file as its creation: `SECURITY DEFINER SET search_path = public` + `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE ... TO service_role` (migration `20260925000003` pattern, L55–82). No exceptions — helpers included.
- Errors use the PTxxx `USING ERRCODE` convention (`PT409` state conflict, `PT422` rule violation) with `HINT` carrying the `ErrorCode` name (migration `20260920000005` L~45 pattern).
- `attendance_settings`/`attendance_setup_progress`: RLS enabled, no public policies (deny-by-default) — every read/write goes through the NestJS admin client with an explicit `tenant_id` filter.
- Wizard step vocabulary is fixed: `'offices' | 'timings' | 'weekly_off' | 'holidays' | 'employees'` (FR-1 order; Holidays is the only skippable step — skipping is a FE concern, the step marker just advances).
- Update `docs/api-contracts.md` in the same change (new section between Reports and Sync, plus the Endpoints tree at L40).

**Ask First:**
- If `attendance_complete_setup` requires the offices/enrolments tables to exist at migration time (e.g. SQL-language body), HALT — PL/pgSQL is the agreed mechanism.
- If completing setup needs to change the `enabled` semantics (kill switch vs wizard-on), HALT and confirm — this spec sets `enabled = true` when setup completes (the PRD's "Owner turns it on through a setup wizard").

**Never:**
- No offices, enrolments, weekly-off or holidays tables in this story (15-3 / 15-5 / 15-7 own those).
- No timezone-editing route — `tenants.timezone` ships with its default; a tenants-profile route to change it is a later story.
- No idempotency interceptor on attendance routes (AD-6 explicitly excludes it; setup start/step-save are naturally idempotent upserts).
- No `getIstDayRange` changes — existing IST utilities stay untouched; `attendance_today()` is additive for attendance RPCs only.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Migration applies to live DB | 10 existing tenants, no timezone column | Column added with DEFAULT 'Asia/Kolkata'; all 10 rows backfilled by the default; trigger `tenants_timezone_guard` attached | — |
| Owner saves an invalid timezone | `tenants.timezone = 'EST'` (not in `pg_timezone_names` / not region-style) | Row unchanged | trigger raises `PT422`, HINT `ATTENDANCE_INVALID_TIMEZONE` |
| Owner saves a non-region name | `timezone = 'UTC'` (valid IANA but not region-style) | Row unchanged | same `PT422` raise |
| Owner saves a valid region name | `timezone = 'Europe/London'` | Row saved | — |
| Owner starts the wizard | `POST /attendance/setup`, no settings row | Upserts `attendance_settings` (enabled=false) + `attendance_setup_progress` (current_step='offices'); 201 | Already completed → 409 `ATTENDANCE_SETUP_ALREADY_COMPLETED` |
| Owner restarts the wizard mid-way | `POST /attendance/setup`, rows exist, not completed | 200 with current state (idempotent — no reset of progress) | — |
| Owner's app saves a step | `PATCH /attendance/setup` `{ currentStep: 'weekly_off' }` | Upsert `attendance_setup_progress` with explicit tenant_id filter; 200 | Invalid step → 422 `VALIDATION_ERROR` (ValidationPipe); not started → 404 `ATTENDANCE_SETUP_NOT_STARTED` |
| Owner resumes | `GET /attendance/setup`, never started | 200 `{ started: false, ... }` (no 404 — FE renders cleanly) | — |
| Owner completes setup | `POST /attendance/setup/complete` → `attendance_complete_setup` | Exclusive tenant lock; ≥1 Office + ≥1 tracked Employee with assignment exist → sets `setup_completed_at`, `enabled = true`; 200 | Gates unmet → `PT422` → 422 `ATTENDANCE_SETUP_INCOMPLETE`; not started → 404 |
| Anon/authenticated calls any attendance function | Direct PostgREST rpc with anon key or user JWT | Function not executable | `42501` (catalog probe pins this) |
| Trigger function called as RPC | `tenants_timezone_guard` via PostgREST | Not an RPC endpoint | `PGRST202` (catalog probe pins this) |

</frozen-after-approval>

## Code Map

Investigation evidence (subagent sweep + live-DB findings, 2026-09-26; all paths relative to `fenzit-be/`):

- **`tenants` table** — `supabase/migrations/20260619185741_create_tenants_and_rpc.sql:6-18`: `id, owner_id, company_name, gstin, address, state_code, service_categories, upi_vpa, created_at, updated_at`. No timezone column. Live DB: 10 tenant rows, 0 attendance/leave tables, `pg_cron` present, `btree_gist` absent (15-3's job), `'Asia/Kolkata'` present in `pg_timezone_names`.
- **PTxxx raise pattern** — `supabase/migrations/20260920000009_reports_retry_requeue.sql:51-55` (`raise exception ... using errcode = 'PT429'`) and `20260920000005_rpc_claim_report_request.sql:~45` (PT409 + header documents the convention); trigger-function shape (`returns trigger`, `set search_path to 'public'`, `drop trigger if exists` + `create trigger`) at `20260920000009:21-65`.
- **AD-3 grant pattern** — `supabase/migrations/20260925000003_default_privileges_no_public_execute.sql:42-82`: default-privilege revoke already exists (L42-43), so new functions need only the per-function triple revoke + `grant execute ... to service_role`. Header `20260925000001:19-26`: every new/changed function repeats revokes + grant in its own migration.
- **Advisory lock precedent** — `20260920000009:44`: `pg_advisory_xact_lock(hashtextextended(new.tenant_id::text, 0))`.
- **Existing updated_at trigger** — `update_updated_at_column` trigger function exists in the repo (pinned by the catalog probe); reuse for the two new tables.
- **PTxxx → HTTP mapping in services** — `src/reports/reports.service.ts:48` (`const PT_IN_FLIGHT_LIMIT = 'PT429'`) and the mapping block L100-109: `error.code === 'PTxxx'` → `throw new HttpException({ error_code, message }, status)`. The GlobalExceptionFilter (`src/common/filters/global-exception.filter.ts:93-101`) renders `{ statusCode, error_code, message, ...extra }` and lifts `retryAfterSeconds` to a header.
- **ErrorCode enum** — `src/common/enums/error-code.enum.ts:16-23`: reports block with `// Reports (Epic 12)` comment; attendance codes append below with `// Attendance (Epic 15)`.
- **Admin client factory** — `src/common/factories/supabase-client.factory.ts:35-43` (`createAdmin()`, service-role); the sanctioned path for all attendance DB calls (migration `20260925000001:9-13`).
- **Controller pattern** — `src/reports/reports.controller.ts:30-119`: `@Controller('reports')` + global `api/v1` prefix (`src/main.ts:33`), `@Roles(Role.OWNER)` per route, `@CurrentUser() user: RequestUser`, `@HttpCode`, Swagger decorators, `:id` routes below the parameterless `@Get()`. RolesGuard is global (`src/app.module.ts:161-162`). ValidationPipe options (`src/common/validation-pipe-options.ts:13-18`): whitelist, transform, 422.
- **DTO style** — `src/reports/dto/create-report-request.dto.ts`: camelCase props, `@ApiProperty(Optional)` + class-validator, shape-only validation (deep checks in the service).
- **Module registration** — `src/reports/reports.module.ts` + `src/app.module.ts:145` (SupabaseModule at 134). AttendanceModule mirrors this with `imports: [SupabaseModule]`.
- **Guarded plain-write precedent** — `src/reports/reports.service.ts:88-98` (insert with explicit tenant_id from JWT) and `:307-313` (`getOwnRowOrThrow` tenant-filtered read, PGRST116→404 at L315-327) — the pattern for setup start/step-save upserts.
- **Integration probe infra** — `test/integration/rls-isolation.integration.spec.ts`: `IS_REAL_DB` L28-30, `maybeIt` L47; the 14-1 catalog pin `maybeIt('Catalog pin: every public RPC rejects anon-key direct calls (Story 14-1)')` L897-1010 with the `RPC_FUNCTIONS` map L918-963 (this story extends the map with the attendance functions + pins the new trigger function as `PGRST202` at the L990-1005 block); schema-pin pattern L1298-1322. No `^(attendance|leave)_` scan exists yet — this story adds the first attendance entries.
- **Unit-test conventions** — `src/reports/reports.service.spec.ts`: `mockAdmin` dispatching on first chained method (~L122-140), chain builders `singleChain`/`updateChain` (L23-48), `expectErrorCode` (L55-66) asserting both status and error_code, per-story `describe` blocks.
- **docs/api-contracts.md** (684 lines): Reports section ends ~L630, Sync starts L631; the attendance section slots between them following the `### <Module> (<story>, <role note>)` + `#### METHOD ... [Bearer JWT, Role: owner]` + Responses-bullets convention; Endpoints tree at L40 needs the new subsection.
- **IST utilities** — `src/common/utils/ist-day-range.util.ts` (`IST_OFFSET_MS`), used by `jobs.service.ts:22`, `users.service.ts:17`, reports params/template — untouched; `attendance_today()` supersedes these only inside attendance code.

## Tasks & Acceptance

**Execution:**
- [ ] `supabase/migrations/20260926000001_tenants_timezone.sql` — `ALTER TABLE public.tenants ADD COLUMN timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata';` + trigger function `tenants_timezone_guard()` (BEFORE INSERT OR UPDATE OF timezone; rejects any value not found in `pg_timezone_names` or without a region part (no `/`); `raise exception ... using errcode = 'PT422', hint = 'ATTENDANCE_INVALID_TIMEZONE'`) + trigger on `public.tenants`. Function gets the AD-3 triple revoke + service_role grant. Apply via Supabase MCP; verify all 10 rows carry 'Asia/Kolkata' and an invalid-name UPDATE raises PT422.
- [ ] `supabase/migrations/20260926000002_attendance_foundation_tables.sql` — create `attendance_settings` (`tenant_id UUID PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE`, `enabled BOOLEAN NOT NULL DEFAULT false`, `setup_completed_at TIMESTAMPTZ`, `created_at/updated_at`) and `attendance_setup_progress` (`tenant_id UUID PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE`, `current_step TEXT NOT NULL CHECK (current_step IN ('offices','timings','weekly_off','holidays','employees'))`, `created_at/updated_at`); RLS enabled on both with **no** policies; `update_updated_at_column` triggers. Apply via MCP; verify.
- [ ] `supabase/migrations/20260926000003_attendance_helpers_and_complete_setup.sql` — create, each with AD-3 grants in-file:
  - `attendance_today(p_tenant_id uuid) RETURNS date` — `(now() AT TIME ZONE (SELECT timezone FROM public.tenants WHERE id = p_tenant_id))::date`, SECURITY DEFINER SET search_path = public.
  - `attendance_lock_tenant(p_tenant_id uuid, p_exclusive boolean) RETURNS void` — `p_exclusive` → `pg_advisory_xact_lock(hashtextextended('tenant:' || p_tenant_id, 0))`, else `pg_advisory_xact_lock_shared(...)` (distinct key-space prefix from employee keys).
  - `attendance_lock_employee(p_employee_id uuid) RETURNS void` — exclusive `pg_advisory_xact_lock(hashtextextended('employee:' || p_employee_id, 0))`.
  - `attendance_complete_setup(p_tenant_id uuid, p_actor_id uuid) RETURNS void` — PL/pgSQL: exclusive tenant lock first; verify `attendance_settings` row exists and `setup_completed_at IS NULL` (else PT409); verify ≥1 `attendance_offices` row and ≥1 tracked employee with an `attendance_office_assignments` row (tables arrive in 15-3/15-7 — function compiles now, is callable then); on success `UPDATE attendance_settings SET setup_completed_at = now(), enabled = true`. PT422 `HINT 'ATTENDANCE_SETUP_INCOMPLETE'` when gates unmet. AD-3 grants.
  - Apply via MCP; verify all four functions in `pg_proc` with the right ACLs (anon/authenticated absent, service_role present).
- [ ] `src/common/enums/error-code.enum.ts` — add `ATTENDANCE_INVALID_TIMEZONE`, `ATTENDANCE_SETUP_NOT_STARTED`, `ATTENDANCE_SETUP_ALREADY_COMPLETED`, `ATTENDANCE_SETUP_INCOMPLETE` under `// Attendance (Epic 15)`.
- [ ] `src/attendance/` new module — `attendance.module.ts` (imports SupabaseModule; registered in `app.module.ts`), `attendance.controller.ts` (`@Controller('attendance/setup')`, `@Roles(Role.OWNER)` on every route, Swagger blocks):
  - `GET /api/v1/attendance/setup` — resume state: reads both tables tenant-scoped; 200 `{ started, currentStep (nullable), setupCompletedAt, enabled }`.
  - `POST /api/v1/attendance/setup` — start: if setup already completed → 409; upsert settings + progress rows (current_step='offices'); 201 on first start, 200 with current state if already started (idempotent).
  - `PATCH /api/v1/attendance/setup` — `UpdateSetupStepDto { currentStep }` (class-validator enum over the fixed vocabulary); guarded upsert with explicit tenant_id filter; not started → 404 `ATTENDANCE_SETUP_NOT_STARTED`.
  - `POST /api/v1/attendance/setup/complete` — `createAdmin().rpc('attendance_complete_setup', { p_tenant_id, p_actor_id })`; maps `error.code === 'PT422'` → 422 `ATTENDANCE_SETUP_INCOMPLETE`, `PT409` → 409; 200 on success.
  - `attendance.service.ts` (tenant-scoped reads/writes via admin client, camelCase row mapping, PTxxx mapping constants) + `dto/` (`SetupStateResponse`, `UpdateSetupStepDto`). File limit ~300 lines; split if it grows.
- [ ] `docs/api-contracts.md` — new `### Attendance setup (Epic 15, Story 15-2, owner only)` section between Reports and Sync; Endpoints tree updated.
- [x] Post-user-confirmation tests (per test-timing rule, only after the user confirms the foundation works): `attendance.service.spec.ts` (mock-admin chain pattern per `reports.service.spec.ts` — start idempotency, step-save tenant filter, PT422/PT409 mapping, not-started 404s), `attendance.controller.spec.ts` (route guards/HttpCodes), catalog-pin extension in `rls-isolation.integration.spec.ts` (attendance functions → anon/authenticated `42501`; `tenants_timezone_guard` → `PGRST202`), plus real-DB probes: invalid-timezone UPDATE rejected with PT422, valid region name accepted, settings/progress schema pin + tenant isolation. **DONE 2026-09-26 — see Tests in Verification.**

**Acceptance Criteria:**
- Given the migrations applied, when `information_schema`/`pg_proc` are inspected, then `tenants.timezone` exists (NOT NULL DEFAULT 'Asia/Kolkata', all 10 rows backfilled), both tables exist with RLS enabled and no public policies, and every new function is SECURITY DEFINER with anon/authenticated denied and service_role granted.
- Given an invalid timezone value, when `UPDATE tenants SET timezone = ...` runs, then the trigger raises PT422 and the row is unchanged; `Asia/Kolkata` and other valid region names succeed.
- Given an owner calling the setup routes, then GET returns a not-started shape before setup, start/step-save persist server-side with explicit tenant_id filters, and complete maps the RPC's PT422 to 422 `ATTENDANCE_SETUP_INCOMPLETE`.
- Given all previously green suites run after the change, then every one stays green (additive change; no existing route or behaviour touched).

### Review Findings (BMAD code review, 2026-09-26 — 4 layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor)

- [x] [Review][Decision — RESOLVED: no policies, deny-by-default] RLS `for all` tenant-isolation policies let any authenticated tenant JWT write `enabled`/`setup_completed_at` directly via PostgREST — a tenant can self-enable the module and fake completion without the gates, the exclusive lock, or `attendance_complete_setup` [supabase/migrations/20260926000002_attendance_foundation_tables.sql:39-47] — the frozen spec said "RLS enabled, **no public policies** (deny-by-default)"; the recorded deviation kept the report_requests-shaped `for all` policy, but unlike a request log this table holds module state, so the WITH CHECK admits owner INSERT/UPDATE/DELETE of the kill-switch and completion timestamp. Choose: (a) SELECT-only policy for authenticated, (b) no policies (deny-by-default, admin-client-only), (c) keep as-is.
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] `getSetupState` never calls `requireTenant` — a no-tenant owner JWT hits `.eq('tenant_id', null)` reads and returns 200 `started=false`, masking missing-company state; the other three routes guard [src/attendance/attendance.service.ts:41]
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] `attendance_today` silently returns NULL for an unknown tenant id (`now() at time zone NULL` → NULL date) — the single source of "today" should fail loud [supabase/migrations/20260926000003_attendance_helpers_and_complete_setup.sql:20]
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] `attendance_start_setup` has no functional probe — restart-must-not-reset-progress (the headline FR-1 guarantee) is never executed against the real DB; add a service-role probe: start, move the step, start again, assert step preserved [supabase/migrations/20260926000004_rpc_attendance_start_setup.sql]
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] `attendance_today` probe asserts only a date-shape regex though the tenant timezone was just set to `Europe/London` — compare against the computed London date so timezone drift fails [test/integration/rls-isolation.integration.spec.ts]
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] `saveStep` has no completed-setup guard — the step marker stays PATCHable after `setup_completed_at` is set; mirror start/complete's 409 [src/attendance/attendance.service.ts:99]
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] `attendance_lock_tenant` treats `p_exclusive = NULL` as a shared lock instead of raising [supabase/migrations/20260926000003_attendance_helpers_and_complete_setup.sql:46]
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] Schema-pin comment says the column lists must stay byte-identical to `readSettings`/`readProgress`, but the service selects `*` — fix the comment to state what the pin actually guards [test/integration/rls-isolation.integration.spec.ts]
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] `docs/api-contracts.md` PATCH route omits the 400 `VALIDATION_ERROR` (no-tenant) response that `saveStep` can produce [docs/api-contracts.md]
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] Controller Swagger blocks omit the 400/500 responses the docs and service define [src/attendance/attendance.controller.ts]
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] `saveStep` ships a guarded UPDATE, not the frozen "guarded admin-client upsert" (correct resolution of the spec-internal 404 contradiction) — record it in the spec deviations [spec Deviations section]
- [ ] [Review][Patch] [x] [Review][Patch — FIXED] Unused `ApiProperty` import in the response model [src/attendance/attendance-response.model.ts:1]
- [x] [Review][Defer] complete-setup Gate 2 ignores office `archived_at` and `users.status` when counting tracked employees [supabase/migrations/20260926000003_attendance_helpers_and_complete_setup.sql:109] — deferred, pre-existing (shapes are AD-8 provisional, reconciled in 15-7 by plan)
- [x] [Review][Defer] No e2e HTTP-boundary spec pins route mounting and the ValidationPipe 422 (sibling modules have one) [src/attendance/attendance.controller.ts] — deferred, add `test/attendance.e2e-spec.ts` when the module grows its 15-3 endpoints
- [x] [Review][Defer] No `^(attendance|leave)_` pg_proc privilege scan (AD-3 asks for one; pg_proc is unreachable via supabase-js per the file's own comment, so coverage is the hand-added RPC map) [test/integration/rls-isolation.integration.spec.ts:922] — deferred, revisit in 15-3 (MCP-side verification)
- [x] [Review][Defer] `SETUP_STEPS` DTO vocabulary and the DB CHECK constraint are duplicated with no cross-pin [src/attendance/dto/update-setup-step.dto.ts] — deferred, both sides are individually tested; a catalog cross-pin needs pg catalog access — revisit 15-3

## Design Notes

**Why enabled=true on completion:** the PRD frames the wizard as the act of turning the module on ("Owner enables the module through a setup wizard"); AD-25's `enabled = false` is then the kill switch that turns it off while keeping history. Splitting "setup complete" from "module on" would leave a state the wizard can't reach. Flagged in Ask-First for renegotiation if the PRD owner intended a separate activation.

**Why the timezone trigger isn't a CHECK:** Postgres cannot reference `pg_timezone_names` in a CHECK constraint; the AD-7 spec mandates the trigger + PT422 path. The trigger only fires on INSERT/UPDATE OF timezone, so row updates that don't touch it pay nothing. AD-7 also requires a *region-style* name (the offset-only zone names like `UTC` are rejected) so `AT TIME ZONE` maths and future DST rules behave predictably.

**Why step saves are plain upserts, not RPCs:** AD-3's conscious exception permits single-row, single-table writes with no side effects as guarded SQL through the admin client. The wizard step marker is exactly that; everything multi-row or lock-requiring (complete_setup) is an RPC.

**Why the RPC ships before its tables:** PL/pgSQL validates function bodies lazily (only syntax at CREATE), so `attendance_complete_setup` compiles against tables that 15-3/15-7 will create. Nothing can call it before the FE wizard exists (15-8), which lands after 15-7. Its gating probes are therefore deferred to 15-7 — recorded in the epic's execution notes.

**Lock key-spacing:** tenant and employee keys derive from distinct text prefixes (`'tenant:'`/`'employee:'`) fed to `hashtextextended`, so an employee id can never collide with a tenant id's slot (AD-5's "no function asks for a tenant lock after an employee lock" ordering is enforced by later stories' code review, not by the helpers).

## Verification

**Commands:**
- `cd fenzit-be && bunx tsc --noEmit` — DONE 2026-09-26: **65 errors == baseline parity** (ee44907), zero from `src/attendance/`.
- `cd fenzit-be && bun run test` — DONE 2026-09-26 (under Node 24.13.0, see deviations): **52 suites, 716/716 passed** — exact 14-2 baseline, nothing regressed (tests are the pre-existing suite; new spec files come post-confirmation).
- Supabase MCP `execute_sql` — probes below.

**Live DB checks (2026-09-26, all via MCP; probe changes rolled back):**
- 4 migrations applied (`20260926000001`..`04`); all 10 tenants carry `timezone = 'Asia/Kolkata'`.
- `tenants_timezone_guard`: `UPDATE timezone='EST'` → `PT422` + hint `ATTENDANCE_INVALID_TIMEZONE`; `'UTC'` (offset-only) → same PT422; `'Europe/London'` → accepted.
- Both tables: RLS enabled with NO policies (review decision — deny-by-default; the temporary tenant-isolation policies were dropped via the corrective MCP apply), updated_at triggers attached; 0 rows (on-demand creation).
- All 5 functions (`attendance_today`, `attendance_lock_tenant`, `attendance_lock_employee`, `attendance_complete_setup`, `attendance_start_setup`): `prosecdef = true`, `search_path=public`, anon/authenticated denied, service_role granted.
- `attendance_today` → `2026-09-26` for the seed tenant (server clock in tenant tz).
- Both lock helpers acquire cleanly; `attendance_complete_setup` with no settings row → `PT409` + hint `ATTENDANCE_SETUP_ALREADY_COMPLETED` (gating probes deferred to 15-7 with the tables).
- `attendance_start_setup` called twice → exactly 1 settings row + 1 progress row (`current_step='offices'`); rolled back, DB left clean.

**Manual checks:**
- DONE 2026-09-26 — routes walked live with real JWTs (local nest watch, owner `cfc7b75a` / tenant `4586040a`; JWTs minted in /tmp, probe rows cleaned up after):
  1. `GET /attendance/setup` before start → **200** `{ started:false, currentStep:null, setupCompletedAt:null, enabled:false }`.
  2. `POST` start → **201** `{ started:true, currentStep:'offices', ..., enabled:false }`; POST again → **200**, `created:false` path, state identical (idempotent resume).
  3. `PATCH` `{currentStep:'weekly_off'}` → **200**; GET confirms persisted; `PATCH {currentStep:'vacation'}` → **422** `VALIDATION_ERROR` with the full step vocabulary in the message.
  4. `POST complete` → **500** with `42P01 relation "public.attendance_offices" does not exist` in the log — the documented pre-15-3 state (fail-loud on missing infrastructure rather than masking it as a gate result; unreachable from the FE, which cannot exist before 15-7). Revisit in 15-7 when the gates become real.
  5. Technician JWT on GET → **403** `FORBIDDEN`.
  - Walkthrough found and fixed 2 defects: (a) resume start returned a pinned 201 — controller now picks 201/200 from `created` via `@Res({passthrough:true})`; (b) `UpdateSetupStepDto.currentStep` had no class-validator decorator, so `whitelist:true` stripped it to `undefined` (PATCH silently became a no-op update → wrong 404, and invalid steps bypassed validation) — `@IsIn(SETUP_STEPS)` added; invalid step now 422 before the service.
  - Note: supabase-js PATCH path was proven DB-side first (identical admin-client update outside the server returned the row), which isolated the defect to the DTO layer.
- Post-walkthrough: `attendance_settings`/`attendance_setup_progress` rows deleted for the probe tenant (0 rows, `timezone` intact) — on-demand creation means the tenant is back to not-started with no residue.
- Tests (unit + integration probes) written after this confirmation per the test-timing rule.

**Tests (2026-09-26, post-confirmation):**
- `src/attendance/attendance.service.spec.ts` — 21 tests, mock-admin chain pattern (per `reports.service.spec.ts`): `getSetupState` started=false/camelCase mapping/tenant-scoped reads/enabled response; `startSetup` first-start `created=true` + exact RPC args, resume `created=false` with the RPC still called (with a pre/post-RPC read sequence on the settings chain), completed → 409 before any RPC, no-tenant → 400 before any client call, RPC failure → 500; `saveStep` payload + tenant-filter eq captured in chain order, empty result → 404 `ATTENDANCE_SETUP_NOT_STARTED`, update failure → 500, no-tenant → 400; `completeSetup` happy path (pre-check un-completed → RPC → enabled state), 404 pre-check, 409 pre-check, `PT422` → 422 `ATTENDANCE_SETUP_INCOMPLETE`, `PT409` race fallback → 409 (from the RPC only — pre-check saw an un-completed row), other → 500, no-tenant → 400.
- `src/attendance/attendance.controller.spec.ts` — 18 tests: delegation for all 4 handlers; the dynamic start route (`reply.code(201)` on first start, `reply.code(200)` on resume, state returned); metadata pins — controller path `attendance/setup`, each handler's method/path (`/` for GET/POST/PATCH, `complete` for the sub-route), `@Roles(Role.OWNER)` on every handler, fixed `@HttpCode(200)` on GET/PATCH/complete, and the declared 201 on start (live status set per-response).
- `test/integration/rls-isolation.integration.spec.ts` — catalog pin extended: 5 attendance RPCs added to `RPC_FUNCTIONS` with real argument names (anon + authenticated both expect `42501` — privilege check fires before any body), `tenants_timezone_guard` added to the `PGRST202` trigger-function block. New real-DB probe "Attendance foundation: timezone guard, table schema pins, settings/progress tenant isolation": seeds probe tenant `…090` (suite's unused id block), then (a) `timezone='EST'` → `PT422` + hint `ATTENDANCE_INVALID_TIMEZONE`, `'Europe/London'` accepted and persisted, seeded default `Asia/Kolkata` pinned; (b) `attendance_today` service-role call returns a `YYYY-MM-DD` date; (c) schema pins byte-identical to `readSettings`/`readProgress` selects; (d) seeded settings+progress rows invisible to bare anon and to a foreign-tenant JWT (both empty, not errors), visible only to service role. Probe cleanup in `finally`; verified post-run via MCP — 0 settings rows, 0 progress rows, probe tenant/owner gone.
- Runs: full unit suite **54 suites, 755/755 passed** (was 716 + 39 new); `bunx tsc --noEmit` **65 errors == baseline parity**; integration spec via `jest --config ./test/jest-e2e.json test/integration/rls-isolation.integration.spec.ts -t "Attendance foundation|Catalog pin"` — 2 passed, rest skipped — with the 4 Supabase env vars exported from `.env` (the `.env` is not `source`-able; it has an unquoted base64 line that aborts `source`).

**Post-review re-run (2026-09-26, after the 12 review fixes):** corrective MCP apply verified live — 0 policies on both tables, `attendance_today` PL/pgSQL (fail-loud), `attendance_lock_tenant` NULL guard; full unit suite **54 suites, 758/758 passed** (3 new guard tests); `bunx tsc --noEmit` **65 errors == baseline parity**; integration probes (catalog pin + foundation probe incl. the new start-RPC functional probe and London-date assertion) **2 passed** against the real DB; DB confirmed clean afterwards (0 settings/progress rows, probe tenant gone).

## Suggested Review Order

**Migrations (foundation first)**

- Timezone column + guard trigger (PT422 raise, region-style rule).
  [`20260926000001_tenants_timezone.sql`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260926000001_tenants_timezone.sql)

- Settings + progress tables (RLS, no policies, CHECK vocabulary).
  [`20260926000002_attendance_foundation_tables.sql`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260926000002_attendance_foundation_tables.sql)

- Helpers + complete_setup RPC (lock key-spacing, gate order, AD-3 grants per function).
  [`20260926000003_attendance_helpers_and_complete_setup.sql`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260926000003_attendance_helpers_and_complete_setup.sql)

**NestJS module**

- Setup routes: guard, DTO validation, tenant-scoped upserts, PTxxx mapping.
  [`src/attendance/attendance.controller.ts`](../../workspace/core/backend/fenzit-be/src/attendance/attendance.controller.ts)
  [`src/attendance/attendance.service.ts`](../../workspace/core/backend/fenzit-be/src/attendance/attendance.service.ts)

**Contracts & catalog pin**

- api-contracts.md section + Endpoints tree.
  [`docs/api-contracts.md:630`](../../workspace/core/backend/fenzit-be/docs/api-contracts.md#L630)

- Catalog-pin extension for the new functions/trigger fn + the real-DB foundation probe.
  [`rls-isolation.integration.spec.ts:897`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L897)

**Tests (post-confirmation)**

- Service: chain mocks, `created` 201/200 semantics, PT422/PT409 mapping, tenant guards.
  [`src/attendance/attendance.service.spec.ts`](../../workspace/core/backend/fenzit-be/src/attendance/attendance.service.spec.ts)

- Controller: delegation, dynamic reply codes, role/path/HttpCode metadata pins.
  [`src/attendance/attendance.controller.spec.ts`](../../workspace/core/backend/fenzit-be/src/attendance/attendance.controller.spec.ts)