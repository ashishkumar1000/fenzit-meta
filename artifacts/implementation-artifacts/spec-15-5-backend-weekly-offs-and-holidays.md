---
title: 'Weekly offs & holidays — tables, effective-dated RPCs, holiday notifications & routes'
type: 'feature'
created: '2026-09-27'
status: 'done'
review_loop_iteration: 1
baseline_commit: '433072a'
context:
  - '{project-root}/artifacts/planning-artifacts/epics-attendance-leave.md'
  - '{project-root}/artifacts/planning-artifacts/architecture/architecture-attendance-leave-2026-09-25/ARCHITECTURE-SPINE.md'
  - '{project-root}/artifacts/planning-artifacts/prds/prd-Fenzo-attendance-2026-09-25/prd.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-15-3-backend-offices-and-office-rules.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Epic 16's day-context helper (AD-22, story 16-1) must resolve `is_weekly_off` and `holiday_id` per employee-date, and the wizard's Weekly-off and Holidays steps (15-8) need somewhere to write — but no weekly-off or holiday data exists yet. FR-18/19/20 have no backing tables, RPCs or routes.

**Approach:** One migration creates three tables: `attendance_weekly_off_defaults (tenant_id, valid daterange, days int[])`, `attendance_weekly_off_overrides (employee_id, tenant_id, valid, days int[])` — both AD-8 exclusion-constrained (`btree_gist` already enabled by 15-3) — and `holidays (tenant_id UNIQUE-paired with holiday_date, name)`. A second migration creates the SECURITY DEFINER RPCs: `attendance_set_weekly_off_default` (AD-8 algorithm, `effective_from = greatest(p_from, attendance_today)`, rejects a 7-day selection with PT422 — FR-18's zero-working-days rule, DB CHECK as authority), `attendance_set_weekly_off_override` / `attendance_remove_weekly_off_override` (same algorithm; removal inserts nothing so the employee falls back to the tenant default from that date — FR-19), and the holiday lifecycle: `attendance_add_holiday` (UNIQUE date → PT409), `attendance_update_holiday` (name only — date immutable), `attendance_remove_holiday` (hard delete; day statuses recompute on read, AD-10), plus the AD-24 preview `attendance_holiday_impact`. Holiday notifications (AD-13) are **wired now, no-op until tracked employees exist**: the insert branch is nested in `IF to_regclass('public.attendance_enrolments') IS NOT NULL THEN … END IF` (the migration-20260926000008 Amendment-2 precedent — PL/pgSQL plans a statement only when first executed), writing `attendance.holiday_added` / `attendance.holiday_removed` rows to `notifications` in the same transaction with tenant-recipient-prefixed dedupe keys. This story also creates `src/attendance/notification-events.ts` — the AD-13 backend registry (source of truth for every future attendance/leave event). A `src/attendance/` extension exposes owner-only routes for weekly offs and holidays; `docs/api-contracts.md` gains the section in the same change.

**Scope decisions locked with the user (2026-09-27):**
- **Leave-overlap branch of `attendance_holiday_impact` is deferred to the Epic 17 leave story** — `leave_requests` / `leave_transition_days` don't exist until then (the FR-9 precedent: behaviour that needs a later epic's data model moves to that epic). 15-5 ships the preview with tracked-employee impact only; Epic 17 extends the function with leave impact and its two ACs (holiday-inside-approved-leave add/remove notifications) are re-tested there.
- **Holiday notifications are wired now and no-op until tracked employees exist** — the same `to_regclass` guard that made `attendance_archive_office` a clean no-op pre-15-7 (Amendment 2). Post-15-7 the branch self-activates; 15-7 owns the final tracked predicate.
- **Spec first, then implement** — this file, reviewed by the user, precedes any migration/code.

**Scope recommendations — user signed off all four as recommended (2026-09-27):**
- **"The default is Sunday" (FR-18) = FE preselection, no DB seeding.** No row is auto-created; absence of a covering row = all 7 days are working days. 15-6's settings/wizard UI preselects Sunday, so the saved default is de facto Sunday. (Alternative rejected as scope creep: recreating 15-2's `attendance_start_setup` to seed `[today, ∞) days={7}`.)
- **Empty `days` array is allowed** (= explicit "no weekly off" / "works all 7 days"). For overrides this is the only way to express "this employee works all week while the tenant has a weekly off" (an override **replaces** the default, AD-22); "remove override" is a separate, distinct operation (row removed → default applies).
- **`attendance.holiday_removed` is emitted for future-date removals to tracked employees**, mirroring `holiday_added` (PRD only mandates the future-add broadcast plus the leave-range cases; symmetric removal avoids a "holiday vanished silently" state).
- **Holiday date is immutable; only `name` is editable.** Changing a date is remove + add (impact and notifications differ per date).

## Boundaries & Constraints

**Always:**
- Migrations start at `20260927000001` (latest in-repo is `20260926000008`; re-verify against MCP `list_migrations` before applying), one concern per file, applied via Supabase MCP.
- Every new function in the same file as its creation: `SECURITY DEFINER SET search_path = public` + `REVOKE EXECUTE … FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE … TO service_role` (AD-3 triple, 15-2/15-3 pattern).
- All three tables: RLS enabled, **no policies** (deny-by-default; every read/write via the NestJS admin client with an explicit `tenant_id` filter), `tenant_id NOT NULL`, `update_updated_at_column` triggers.
- AD-8 on both weekly-off tables: `valid DATERANGE NOT NULL CHECK (NOT isempty(valid))` + `EXCLUDE USING gist (<owner key> WITH =, valid WITH &&)`. The shared algorithm exactly: `effective_from = greatest(p_effective_from, attendance_today(p_tenant_id))`; delete the owner's ranges starting on/after `effective_from`; clip the covering range's upper bound to `effective_from`; insert `[effective_from, ∞)` — **unless** the change is a removal (or empty-days set), which clips/deletes and inserts nothing.
- `days INTEGER[]` authority: DB CHECKs `days <@ ARRAY[1..7]` (ISO weekday numbers, 1=Mon..7=Sun) and `cardinality(days) < 7` (at least one working day remains — FR-18); DTO mirrors (ints 1–7, unique, max 6 items, empty allowed). RPC sorts + dedupes the array before insert.
- `greatest()` clamp, not a 422: a past `effectiveFrom` silently becomes today (AD-8 step 1 literal; "dates before it are unchanged").
- Exclusive tenant lock (`attendance_lock_tenant(p_tenant_id, true)`) inside every write RPC (all mutate range sets or fan out notifications).
- Weekly-off override target must be a tenant member (PT404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`); no tracked gate pre-15-7 (enrolments don't exist; the override is inert until the employee is enrolled — 15-7 owns the tracked predicate).
- Holiday UNIQUE violation (`23505` on `(tenant_id, holiday_date)`) → PT409 HINT `ATTENDANCE_HOLIDAY_TAKEN`; unknown holiday → PT404 `ATTENDANCE_HOLIDAY_NOT_FOUND`.
- Notifications (future dates only, `p_date > attendance_today`): same-transaction inserts with `entity_type='attendance'`, `entity_id=<holiday uuid>`, camelCase self-contained payload (`holidayName`, `holidayDate`), dedupe key `<tenantId>:<eventType>:<recipientId>:<holidayId>` (the 14-2 recipient-prefixed convention — plain `<tenantId>:<eventType>:<entityId>` collides across recipients). The recipient query sits inside its own `IF to_regclass('public.attendance_enrolments') IS NOT NULL THEN … END IF` branch and is **never AND-ed into one condition** (Amendment-2 planning pitfall).
- Update `docs/api-contracts.md` in the same change (section after Offices, plus the Endpoints tree).

**Ask First:**
- If `attendance_holiday_impact`'s tracked-employee branch cannot be expressed behind the `to_regclass` guard without referencing 15-7 columns in a way PL/pgSQL plans eagerly, HALT and confirm the fallback.
- If the wizard (15-8) turns out to need a "weekly-off step completed" marker beyond writing real rows (AD-25 says it doesn't), confirm before touching `attendance_setup_progress` semantics.

**Never:**
- No enrolments/assignments/leave tables here (15-7 / Epic 17 own those); no `attendance_day_context` or `is_weekly_off` resolution here (16-1 reads these tables via AD-22).
- No employee/technician-facing read route for "my weekly offs" (FR-19's employee visibility arrives with the 15-10 onboarding / 19-6 self-view reads; the FE registry mirror of `notification-events.ts` belongs to 15-6).
- No idempotency interceptor on these routes (AD-6 excludes attendance; DB uniques + dedupe keys bound the blast radius).
- No holiday seeding/preset lists (FR-20 out of scope), no per-employee holidays (out of scope).
- No soft-delete/archive on holidays — FR-20 says remove, and AD-10 recomputes day statuses on read.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Migration applies to live DB | no weekly-off/holiday tables | 3 tables created, RLS enabled, no policies, exclusion constraints on both weekly-off tables, `UNIQUE (tenant_id, holiday_date)` on holidays, updated_at triggers | — |
| Owner sets tenant default Sat+Sun | `PUT /weekly-offs { days:[6,7] }` (no effectiveFrom) | RPC: `[today, ∞)` row; 200 with the resolved default (days, validFrom) | Unknown tenant → PT404 `ATTENDANCE_TENANT_NOT_FOUND` (fail-loud `attendance_today`) |
| Owner sets a default leaving zero working days | `days:[1..7]` | Nothing saved | 422 `ATTENDANCE_NO_WORKING_DAYS` (DTO pre-DB; RPC PT422 + DB CHECK `23514` as backstop) |
| Owner sets a default effective next week | `days:[7], effectiveFrom: 2026-10-05` | Covering range clipped at 2026-10-05; new row `[2026-10-05, ∞)`; earlier dates unchanged | — |
| Owner re-sets the same-day future default | second same-day edit | Future range deleted and replaced — exclusion holds, no zombie ranges | — |
| Owner sets an override for a tenant employee | `PUT /weekly-offs/overrides/:employeeId { days:[5] }` | Override row `[today, ∞)`; 200 | Non-member/unknown employee → 404 `ATTENDANCE_EMPLOYEE_NOT_FOUND` |
| Owner removes an override effective today | `DELETE /weekly-offs/overrides/:employeeId` | Covering range clipped at today, nothing inserted — employee reads the tenant default from today; idempotent no-op if no covering range | 404 for non-member employee; 200 otherwise |
| Owner reads weekly offs | `GET /weekly-offs`, `GET /weekly-offs/overrides` | Default + per-employee overrides with current/upcoming picks (fetch-and-pick model vs `attendance_today`); empty → 200 `[]`/`{ default: null, overrides: [] }` (never 404) | — |
| Owner adds a holiday on a taken date | `POST /holidays { date, name }` where date exists | Nothing saved | 409 `ATTENDANCE_HOLIDAY_TAKEN` |
| Owner adds a future holiday, pre-15-7 | no `attendance_enrolments` table | Row saved; **zero notifications** (guard branch unreached) — correct: nobody can be tracked yet | — |
| Owner adds a future holiday, post-15-7 | tracked employees exist | Row saved + one `attendance.holiday_added` notification per tracked employee, same transaction; dedupe key blocks RPC-retry duplicates | Dedupe `23505` impossible by key construction |
| Owner adds a past holiday | `date < today` | Row saved, no notifications (day statuses recompute on read) | — |
| Owner renames a holiday | `PATCH /holidays/:id { name }` | Guarded UPDATE; 200 | Unknown id → 404 `ATTENDANCE_HOLIDAY_NOT_FOUND` |
| Owner tries to change a holiday's date | `PATCH /holidays/:id { date }` | Rejected | 422 `VALIDATION_ERROR` (date not accepted by the update DTO) — remove + add is the documented path |
| Owner removes a future holiday | `DELETE /holidays/:id` | Row deleted; post-15-7 + tracked employees → `attendance.holiday_removed` notifications; pre-15-7 zero | Unknown id → 404 |
| Owner previews holiday impact | `GET /holidays/impact?date=…` | `{ date, affectedEmployees: [{ employeeId, employeeName }] }` — empty pre-15-7 (guard, **not** fail-loud: 15-6's walkthrough calls it before 15-7 exists, the exact trap the 15-4 archive amendment fixed); leave-overlap rows arrive with Epic 17 | Bad date → 422 |
| Anon/authenticated calls any new function | Direct PostgREST rpc | Function not executable | `42501` (catalog probe pins this) |
| Any route called by a technician | JWT role ≠ owner | 403 FORBIDDEN on every handler | — |

</frozen-after-approval>

## Code Map

Investigation evidence (2026-09-27; paths relative to `fenzit-be/`; ⟨15-3⟩ = carried forward from the verified 15-3 code map):

- **Migration numbering** — latest in-repo is `20260926000008_archive_blocker_table_guard.sql`; re-verify via MCP `list_migrations` before applying, then start at `20260927000001`.
- **`btree_gist` already enabled** — 15-3's migration `20260926000005`; no re-enable needed (but `CREATE EXTENSION IF NOT EXISTS` is harmless if included).
- **AD-8 algorithm + AD-3 triple + RLS-no-policies + guarded-UPDATE + fetch-and-pick precedents** — `20260926000006_rpc_attendance_office_lifecycle.sql` (rules RPC = the algorithm to copy), `20260926000002` (no-policies shape), `offices.service.ts` (requireTenant guard, PTxxx→HTTP mapping constants, camelCase mapping, fetch-and-pick rule selection), `offices-response.model.ts` (pure pick model to mirror for weekly-off ranges). ⟨15-3⟩
- **`to_regclass` guard precedent** — `20260926000008_archive_blocker_table_guard.sql`: nested `IF to_regclass(...) IS NOT NULL THEN` branch, probe never AND-ed into one condition (PL/pgSQL plans lazily; the wrong shape still 42P01s at plan time). Holiday-notification recipient queries copy this shape exactly.
- **Composite-FK hardening precedent** — `20260926000007`: 15-3 review decision added `UNIQUE (id, tenant_id)` on the parent + composite child FK. This story mirrors it: `UNIQUE (id, tenant_id)` on `users` + `(employee_id, tenant_id) → users(id, tenant_id)` on overrides, `(tenant_id)` pairing on defaults/holidays.
- **Notifications insert contract** — `20260909000002` (columns, broadcast trigger) + `20260925000005` (entity_type/entity_id/dedupe_key; **mandatory recipient-prefixed key format** recorded in-file). `job_id` is nullable since `20260920000008`; holiday rows insert `job_id NULL`.
- **AD-13 event naming** — `attendance.<event>` / `leave.<event>`, snake_case after the dot, backend registry `src/attendance/notification-events.ts` as source of truth (does not exist yet — this story creates it with the two holiday events; FE mirrors it in 15-6).
- **PTxxx raise + HINT pattern** — `20260920000005_rpc_claim_report_request.sql` ⟨15-3⟩; error codes appended under `// Attendance (Epic 15)` in `src/common/enums/error-code.enum.ts` (currently ends at `ATTENDANCE_OFFICE_ARCHIVE_BLOCKED`).
- **Advisory lock + today helpers exist** — `attendance_lock_tenant` / `attendance_lock_employee` / fail-loud `attendance_today` in `20260926000003`. No new helpers. ⟨15-3⟩
- **Module layout** — `src/attendance/attendance.module.ts` currently registers attendance/setup + attendance/offices controllers. This story adds `weekly-offs.controller.ts|service.ts` (`@Controller('attendance/weekly-offs')`) and `holidays.controller.ts|service.ts` (`@Controller('attendance/holidays')`) — split files per the ~300-line rule; DTOs in `dto/` (`weekly-off.dto.ts` with shared `days` array validators, `holiday.dto.ts`).
- **Controller conventions** — `@Roles(Role.OWNER)` per route, `:id`/`:employeeId` UUID guard → 400 (the 15-3 `requireOfficeId` defer-resolution pattern), `@HttpCode`, Swagger blocks, ValidationPipe 422, GlobalExceptionFilter `extra` (blocker-list shape reused for the impact preview body). ⟨15-3⟩
- **Integration probe infra** — `test/integration/rls-isolation.integration.spec.ts` `RPC_FUNCTIONS` map gains the 7 new functions (anon + authenticated → `42501`); schema-pin pattern gains the 3 tables; probe ids follow the 096+ series with fresh renumbering. `test/attendance.e2e-spec.ts` extends with the new route groups (403 technician, 422 validation, mounting).
- **api-contracts.md** — Attendance setup (15-2) then Offices (15-3) sections; this story's Weekly offs + Holidays section slots after Offices; Endpoints tree updated. Note in the Holidays entry that leave-overlap impact rows arrive with Epic 17.
- **Unit-test conventions** — mock-admin chain pattern, `expectErrorCode` (15-2). ⟨15-3⟩

## Tasks & Acceptance

**Execution:**
- [x] `supabase/migrations/20260927000001_weekly_off_and_holiday_tables.sql` — create:
  - `attendance_weekly_off_defaults` (`id UUID PK DEFAULT gen_random_uuid()`, `tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE`, `valid DATERANGE NOT NULL CHECK (NOT isempty(valid))`, `days INTEGER[] NOT NULL CHECK (days <@ ARRAY[1,2,3,4,5,6,7] AND cardinality(days) < 7)`, `created_at/updated_at`, `EXCLUDE USING gist (tenant_id WITH =, valid WITH &&)`).
  - `attendance_weekly_off_overrides` (`id`, `tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE`, `employee_id UUID NOT NULL`, `valid`, `days` (same CHECKs), `created_at/updated_at`, `EXCLUDE USING gist (employee_id WITH =, valid WITH &&)`) + hardening: `UNIQUE (id, tenant_id)` on `users`, composite FK `(employee_id, tenant_id) → users(id, tenant_id) ON DELETE RESTRICT` (the 15-3 review decision pattern; history never cascaded).
  - `holidays` (`id UUID PK DEFAULT gen_random_uuid()`, `tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE`, `holiday_date DATE NOT NULL`, `name TEXT NOT NULL` (≤80 mirrored in DTO), `created_at/updated_at`, `UNIQUE (tenant_id, holiday_date)`).
  - RLS enabled, no policies, `update_updated_at_column` triggers on all three. Apply via MCP; verify schema + exclusions + unique index live.
- [x] `supabase/migrations/20260927000002_rpc_weekly_off_and_holiday_lifecycle.sql` — seven functions, each with the AD-3 triple in-file:
  - `attendance_set_weekly_off_default(p_tenant_id, p_actor_id, p_days int[], p_effective_from date) RETURNS void` — exclusive tenant lock; `cardinality = 7` → PT422 HINT `ATTENDANCE_NO_WORKING_DAYS`; sort+dedupe; AD-8 algorithm with `effective_from = greatest(p_effective_from, attendance_today)`; empty `p_days` → clip+delete only, no insert.
  - `attendance_set_weekly_off_override(p_tenant_id, p_actor_id, p_employee_id, p_days int[], p_effective_from date) RETURNS void` — same validation/algorithm keyed on `employee_id`; employee must be a tenant member else PT404 HINT `ATTENDANCE_EMPLOYEE_NOT_FOUND`.
  - `attendance_remove_weekly_off_override(p_tenant_id, p_actor_id, p_employee_id, p_effective_from date) RETURNS void` — AD-8 clip+delete, no insert; idempotent when no covering range.
  - `attendance_add_holiday(p_tenant_id, p_actor_id, p_holiday_date date, p_name text) RETURNS uuid` — `23505` → PT409 HINT `ATTENDANCE_HOLIDAY_TAKEN`; **future dates** insert `attendance.holiday_added` notifications to tracked employees inside the `to_regclass('public.attendance_enrolments')` guard branch (predicate: enrolment covers the date AND `attendance_settings.setup_completed_at IS NOT NULL`; inert until 15-7, then 15-7 owns its final shape); returns holiday id.
  - `attendance_update_holiday(p_tenant_id, p_actor_id, p_holiday_id, p_name) RETURNS void` — guarded single-row UPDATE (name only).
  - `attendance_remove_holiday(p_tenant_id, p_actor_id, p_holiday_id) RETURNS void` — PT404 unknown; delete; **future dates** emit `attendance.holiday_removed` behind the same guard.
  - `attendance_holiday_impact(p_tenant_id, p_date date) RETURNS TABLE(employee_id uuid, employee_name text)` — AD-24 preview; tracked-employee branch behind the same `to_regclass` guard (returns empty pre-15-7 — the 15-6 walkthrough must not 42P01); leave-overlap extension documented in-file as Epic 17's.
  - `src/attendance/notification-events.ts` created in the same change (AD-13 registry): the two events with recipient rule, payload fields, dedupe-key shape, entity type — the file every later attendance/leave emitter extends.
  - Apply via MCP; ACL verification for all seven functions.
- [x] `src/common/enums/error-code.enum.ts` — add `ATTENDANCE_NO_WORKING_DAYS`, `ATTENDANCE_EMPLOYEE_NOT_FOUND`, `ATTENDANCE_HOLIDAY_TAKEN`, `ATTENDANCE_HOLIDAY_NOT_FOUND` under `// Attendance (Epic 15)`.
- [x] `src/attendance/weekly-offs.service.ts` + `weekly-offs.controller.ts` + `dto/weekly-off.dto.ts` + a `weekly-offs-response.model.ts` pure model (fetch-and-pick ranges against `attendance_today`):
  - `GET /api/v1/attendance/weekly-offs` — tenant default history with current/upcoming picks + `GET …/weekly-offs/overrides` — per-employee current overrides.
  - `PUT /api/v1/attendance/weekly-offs` — `days` (ints 1–7, unique, ≤6, empty allowed) + optional `effectiveFrom` → default RPC.
  - `PUT /api/v1/attendance/weekly-offs/overrides/:employeeId` + `DELETE …/overrides/:employeeId` (optional `effectiveFrom` query, default today) → override RPCs.
- [x] `src/attendance/holidays.service.ts` + `holidays.controller.ts` + `dto/holiday.dto.ts`:
  - `GET /api/v1/attendance/holidays` — tenant-scoped, ordered by date (FE 15-6 groups upcoming/past); `POST …` (date + name → RPC, 201); `PATCH …/:id` (name only); `DELETE …/:id` (204); `GET …/impact?date=` → `{ date, affectedEmployees }`.
- [x] Register both controllers in `attendance.module.ts`; keep every file ≤ ~300 lines.
- [x] `docs/api-contracts.md` — `### Attendance weekly offs & holidays (Epic 15, Story 15-5, owner only)` after the Offices section; Endpoints tree updated; Epic-17 leave-impact note included.
- [x] Post-user-confirmation tests (per the test-timing rule, only after the user confirms the routes work live): `weekly-offs.service.spec.ts`, `weekly-offs.controller.spec.ts`, `holidays.service.spec.ts`, `holidays.controller.spec.ts`, `weekly-offs-response.model.spec.ts`, `notification-events` registry spec; `test/attendance.e2e-spec.ts` extensions; `rls-isolation.integration.spec.ts` — 7 new RPCs in the 42501 pin, schema pins for the 3 tables, real-DB probes (AD-8 clipping, empty-days clear, override removal fallback, 7-day reject 23514/PT422, holiday PT409/PT404, impact empty pre-15-7, notification guard branch unreached = zero rows).

**Acceptance Criteria:**
- Given the migrations applied, when the catalog is inspected, then all three tables exist with RLS enabled and no policies, both exclusions + the holiday unique constraint exist, `days` CHECKs are in place, and every new function is SECURITY DEFINER with anon/authenticated denied and service_role granted.
- Given an owner setting the tenant default to Saturday + Sunday effective today, when the RPC runs, then one `[today, ∞)` row exists; a 7-day selection is rejected (422 pre-DB, PT422 + `23514` backstop); a future-dated change clips the covering range and leaves all earlier dates on their previous rule.
- Given an owner setting then removing a per-employee override, when the removal RPC runs, then no override covers any date from the chosen date onward and the employee's weekly off resolves to the tenant default from that date (removal inserts nothing; a second removal is an idempotent no-op).
- Given an owner adding a holiday on a unique future date, when the RPC runs, then the row is saved; pre-15-7 zero notifications are inserted (guard branch unreached); a duplicate date is rejected with `ATTENDANCE_HOLIDAY_TAKEN`; a removal deletes the row and emits nothing pre-15-7.
- Given the impact preview, when called for any date, then it returns 200 with `affectedEmployees: []` pre-15-7 (never a 42P01), and the function is documented as Epic-17's extension point for leave impact.
- Given all previously green suites run after the change, then every one stays green (additive change; no existing route or behaviour touched).

### Review Findings

BMAD code review 2026-09-27 (4 layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 33 raw findings triaged). Acceptance audit verdict: no AC unmet, no frozen constraint violated; unit suite re-run green (63 suites / 971 tests). All three decisions resolved (recommended options), all 10 patches applied, defer #2 fixed outright; post-fix suites: 63/972 unit, 17/349 real-DB.

**Decision needed:**
- [x] [Review][Decision] GET /holidays stale-tenant behaviour diverges from sibling reads — `listHolidays` is a plain read (never calls `attendance_today`), so an unknown/stale tenant gets `200 []`, while GET weekly-offs, GET overrides and GET impact all fail loud `404 ATTENDANCE_TENANT_NOT_FOUND` via `attendance_today`. **Resolved: harmonise — `listHolidays` now resolves tenant today first (shared `resolveTenantToday` helper), unknown tenant → 404; swagger + api-contracts + tests updated.**
- [x] [Review][Decision] `p_actor_id` is dead in all six lifecycle RPCs — declared, passed by the services, never referenced in any function body (no audit column exists to receive it). **Resolved: drop now (pre-launch) — migration `20260927000005_drop_dead_actor_id_param.sql` drops the six old signatures explicitly and recreates them without the param (bodies byte-identical); services stop passing it; 15-2/15-3 RPCs untouched.**
- [x] [Review][Decision] `holidays` naming + missing name CHECK — the table is the module's only non-`attendance_`-prefixed table (spec-frozen name), and `holidays.name` has no DB CHECK (non-empty/≤80) while the `days` rules are triple-enforced (DTO + PT + CHECK). **Resolved: accept as spec-frozen — NestJS service is the only sanctioned writer; DTO enforces.**

**Patches:**
- [x] [Review][Patch] api-contracts.md + swagger contract corrections: "never 404" is false for GET weekly-offs and GET overrides (stale tenant → 404 via `attendance_today`); 404 lines missing on GET weekly-offs, GET overrides, POST holidays and GET impact (docs say "200 — always"); "(or unknown tenant)" wording on PATCH/DELETE holidays (docs + swagger) and override PUT/DELETE (swagger) — an unknown tenant actually raises `ATTENDANCE_TENANT_NOT_FOUND`, a distinct code, because both RPCs call `attendance_today` first; PUT weekly-offs 422 line conflates `ATTENDANCE_NO_WORKING_DAYS` with a malformed `effectiveFrom` (which returns `VALIDATION_ERROR`); override PUT/DELETE omit the malformed-date `422 VALIDATION_ERROR`. — **Applied: 10 corrections in api-contracts.md; 404 @ApiResponse lines added/renamed in both controllers.**
- [x] [Review][Patch] `weekly-offs.service.ts` is 358 lines — over the ~300-line rule (spec execution bullet "keep every file ≤ ~300 lines") — with `requireTenant`/`internalError`/`throwRpcError`/HINT constants duplicated near-verbatim in `holidays.service.ts`, and `UUID_PATTERN` at copies #4/#5 across the two new controllers. Extract shared attendance RPC helpers + one shared UUID pattern; split the service. — **Applied: `src/attendance/attendance-rpc.helpers.ts` (requireTenant, resolveTenantToday, error factories, HINT constants), `src/common/utils/uuid-pattern.util.ts`, new `weekly-offs.repository.ts`; weekly-offs.service now ~250 lines; every file ≤ ~300.**
- [x] [Review][Patch] `today()` lacks the resolved-null guard — `createHoliday` maps null data to a 500, but `today()` returns `data as string` unchecked; a contract break silently corrupts the current/next picks. — **Applied: shared `resolveTenantToday` throws internal 500 on a null resolution; used by both services.**
- [x] [Review][Patch] Dead `user` parameter in `readOverrideDetail`. — **Applied: removed (repository function takes `admin, tenantId, employeeId?`).**
- [x] [Review][Patch] Misleading 500 from `readEmployeeNames` — logs "Failed to read employee names" but throws "Failed to read weekly-off overrides". — **Applied: message corrected in the repository.**
- [x] [Review][Patch] PATCH date-immutability guard untested over HTTP — the existing e2e sends `{date}` only, so the ValidationPipe 422s on the missing `name` before `rejectDateKey` runs (the test's own comment admits this); add a `{date, name}` case — the only shape that reaches the guard — and align the test name. — **Applied: new e2e case `{date, name}` → 422 from the raw-body guard with zero RPC calls; `{date}`-only case renamed to name the pipe path.**
- [x] [Review][Patch] Record the 15-7 follow-up for the never-executed SQL — the notification fan-out literals (event_type, payload keys, dedupe shape) and migration-03's display-name fallback queries have zero executable coverage by design (`to_regclass`-gated until 15-7; drift between the SQL literals and `ATTENDANCE_NOTIFICATION_EVENT_REGISTRY` ships undetected); pin "assert persisted notification rows against the registry in the 15-7 journey probe" as a carried task so the risk is owned. — **Applied: bullet in `deferred-work.md`.**
- [x] [Review][Patch] `test:e2e:real` crashes with a raw ENOENT when `.env` is missing — add an existence guard mirroring the Bun-detection guard. — **Applied: package.json guard checks `.env` and prints the fix (copy `.env.example`) before running jest.**
- [x] [Review][Patch] `test:e2e:real` is undocumented — README.md and docs/development-guide.md list only `bun run test:e2e`; the real-DB runner (and its real-Node requirement) belongs in both. — **Applied: script rows in both tables + a "Real-DB probes" section in development-guide.md.**
- [x] [Review][Patch] No HTTP-level case for the 400 no-tenant owner path on the new routes — the shared `requireTenant` guard is unit-covered only; one e2e case (JWT without `tenantId` → 400 `VALIDATION_ERROR`) proves the wiring. — **Applied: e2e mints a `tenantId: null` owner JWT and asserts 400 VALIDATION_ERROR with zero RPC calls.**

**Deferred:**
- [x] [Review][Defer] Post-write re-read outside the tenant lock — the weekly-off writes respond via an unlocked re-read after the RPC commits, so a concurrent owner write can interleave into the response. Tolerable (owner-only, lock-serialised writes, next read correct); the fix means RPCs return state — an AD-3 contract change. Revisit if 16-x shows a real need. [src/attendance/weekly-offs.service.ts:95,153,179]
- [x] [Review][Defer] Live `attendance_holiday_impact` lost the in-file EPIC 17 extension-point comment — migration 03's `create or replace` shipped without it; it survives in migration 02 and api-contracts.md. ~~Restore when Epic 17 extends the function~~ **Fixed during review follow-up: `20260927000006_restore_impact_epic17_comment.sql` re-creates the function (body byte-identical to migration 03's fix) with the EPIC 17 comment restored above it; applied + verified live.** [supabase/migrations/20260927000003_employee_name_phone_column_fix.sql:21-50]

Dismissed (8): migration-03 coalesce nullability (users.country_code/phone_number are NOT NULL — unreachable); DTO max-6 → service guard (sanctioned post-freeze by the Verification section); response shape vs matrix cell (sanctioned by the Response-shape note); migration-02 pre-ruling override body (corrected by 04 by design — applied migrations immutable); probe-id numbering (justified in-file); corrective migrations inside one changeset (already recorded in spec Verification + sprint-status); unbounded list reads (fine at PRD tenant scale); missing 500-path unit specs (diminishing returns — error mapping proven by sibling tests).

## Design Notes

**Why the zero-working-days rule lives in both DTO and DB:** FR-18's consequence is a product invariant, so the DB CHECK (`cardinality(days) < 7`) is the authority (NFR-4); the DTO mirror gives the FE a pre-DB 422 instead of a raw `23514` — the exact 15-3 review finding (cross-field rules DTO-mirrored) applied from day one.

**Why weekly-off edits allow today, unlike office rules' forced tomorrow:** AD-8 step 1 forces tomorrow only for office rules and checked-in-today reassignments. FR-18/19 say "effective from a date the Owner picks (default today)" — so `greatest(p_from, today)` with no +1. Past dates are never editable ("dates before it are unchanged" — the clamp), and the AD-8 delete-then-clip keeps history untouched.

**Why removal is clip-without-insert, not a delete of all ranges:** FR-19's "falls back to the tenant default **from that date**" — earlier override dates keep their override. Deleting the covering range would rewrite history; clipping it at `effective_from` is the same AD-8 algorithm with the final insert omitted.

**Why holiday notifications use the Amendment-2 guard instead of failing loud:** the impact preview and the add/remove RPCs are called by 15-6's UI *before* 15-7 ships — fail-loud 42P01s would break the 15-6 device walkthrough exactly the way the archive blocker probe broke 15-4's. A guard branch keeps 15-5 shippable and self-activates when 15-7 creates `attendance_enrolments`; 15-7's review owns re-verifying the branch (tracked in this spec's Verification section and 15-3's 15-7 note).

**Why the dedupe key embeds the recipient:** the 14-2 partial unique index is global on `dedupe_key` alone. One holiday fans out to N recipients, so `<tenantId>:<eventType>:<entityId>` would 23505 on the second recipient. The recipient-prefixed form the migration comment sanctions keeps keys globally unique per row while still bounding RPC-retry duplicates.

**Why `notification-events.ts` starts here:** AD-13 names it the source of truth, and this story emits the first `attendance.*` events. Starting it now (two events, full metadata) means every later epic (16 fake-location, 17 leave lifecycle, 19 reminders) extends a registry instead of inventing per-story contracts.

**Why no employee-facing read route yet:** technicians have no attendance UI until 15-10 and no day-status reads until 16-1; shipping `GET /me/weekly-offs` now would be dead surface. FR-19's employee visibility is honoured when the UI that renders it exists.

## Verification

### Applied 2026-09-27 (implementation, pre-tests)

**Migrations** (via Supabase MCP, project `pnlvreaijzslfymlnoti` — all three recorded in `list_migrations` as `20260926193958/194012/194216`):
- `20260927000001_weekly_off_and_holiday_tables.sql` — both weekly-off tables (weekday + `cardinality(days) < 7` + `NOT isempty(valid)` CHECKs, GIST exclusions on `tenant_id`/`employee_id`, composite-FK hardening with `UNIQUE (id, tenant_id)` on `users`), `holidays` with `UNIQUE (tenant_id, holiday_date)`; RLS enabled, zero policies, `update_updated_at_column` triggers. Numbering re-verified against `list_migrations` first (latest applied was `20260926000008`).
- `20260927000002_rpc_weekly_off_and_holiday_lifecycle.sql` — all seven functions SECURITY DEFINER `SET search_path = public` with the AD-3 triple.
- `20260927000003_employee_name_phone_column_fix.sql` — same-day amendment: `attendance_holiday_impact` (this story) and `attendance_office_archive_blockers` (15-3) had been written against `users.phone`, which `20260620000002` split into `country_code` + `phone_number`. Lazy PL/pgSQL planning let both apply cleanly and left the defect dormant (`42703` on first post-15-7 call). Both re-created with `coalesce(nullif(name,''), '+' || country_code || phone_number, 'Unknown employee')`; AD-3 triple restated in-file (the `20260926000008` precedent).

**Catalog verification (MCP):** all three tables live with RLS on / 0 policies / triggers; all CHECKs, both exclusions, the holiday unique and `users_id_tenant_id_key` present as specified; the full `^(attendance|leave)_` `pg_proc` scan shows every one of the 16 functions `prosecdef = true` with ACLs `{postgres, service_role}` only — `has_function_privilege` pins anon/authenticated `false`, service_role `true` (AD-3).

**PL/pgSQL functional probes** (temp `probe_results` table, everything rolled back and verified clean):
- default set with unsorted+duplicated input → one row `[today, ∞)` with canonical `days {6,7}` (sort+dedupe proven).
- 7-day selection → `PT422` HINT `ATTENDANCE_NO_WORKING_DAYS`; direct 7-day insert → `23514` (CHECK backstop); overlapping direct inserts → `23P01` (exclusion); cross-tenant override insert → `23503` (composite FK).
- future-dated edit → covering range clipped at the chosen date, earlier dates unchanged; same-day re-edit replaces the future range (no zombies); empty `days` → clip+delete only, zero rows.
- override: set `[today, ∞)`; non-member employee → `PT404` HINT `ATTENDANCE_EMPLOYEE_NOT_FOUND`; removal → clip-without-insert, second removal an idempotent no-op.
- holidays: future add returns the id with **zero notifications** (guard branch unreached — pre-15-7 contract); past add silent; duplicate date → `PT409` HINT `ATTENDANCE_HOLIDAY_TAKEN`; rename works, unknown id → `PT404` on both update and remove; removal deletes the row with zero notifications.
- impact preview → empty result, no `42P01` (Amendment-2 guard holds); unknown tenant → `PT404` HINT `ATTENDANCE_TENANT_NOT_FOUND` (fail-loud `attendance_today`).

**Live HTTP walkthrough** (owner + technician HS256 JWTs minted from `SUPABASE_JWT_SECRET`, Nest on :3000, probe tenant/users created then cleaned):
1. GET weekly-offs → `200 {default:null,next:null,history:[]}` (empty state, never 404).
2. PUT `{days:[6,7]}` → `200`; GET → current pick `[2026-09-27, ∞)`; PUT future `{days:[7], effectiveFrom:2026-10-05}` → `200` with clipped covering range + `next`; PUT past `effectiveFrom:2026-01-01` → silently clamped to today.
3. PUT 7-day → `422` (see fix below); `{days:[7,7]}` / `{days:[0]}` / `effectiveFrom:2026-02-30` → `422 VALIDATION_ERROR` (DTO shape).
4. Overrides: empty list `[]` → `200`; PUT `{days:[5]}` → `200` with `employeeName`; PUT empty `days` → `200` (works-all-7 override); DELETE → `200 {current:null}` and second DELETE idempotent; malformed `:employeeId` → `400`; unknown employee → `404 ATTENDANCE_EMPLOYEE_NOT_FOUND`; PUT 7-day → `422 ATTENDANCE_NO_WORKING_DAYS`.
5. Holidays: empty list `200 []`; POST future → `201 {id,date,name}`; duplicate → `409 ATTENDANCE_HOLIDAY_TAKEN`; POST past date → `201` (silent); list ascending; PATCH rename → `200`; PATCH with a `date` key → `422` (raw-body check — the global pipe strips unknown keys); PATCH/DELETE malformed id → `400`, unknown id → `404 ATTENDANCE_HOLIDAY_NOT_FOUND`; DELETE → `204`; `impact?date=` → `200 {affectedEmployees:[]}` pre-15-7; `impact?date=2026-13-01` → `422`.
6. Technician JWT → `403` on both route groups; no JWT → `401`.
7. Zero `attendance.holiday_*` notification rows after the whole walkthrough (guard contract) — probe tenant/users/rows deleted, DB verified clean.

**Fix found by the walkthrough** (folded into the implementation):
- The 7-day selection surfaced as generic `VALIDATION_ERROR` from `@ArrayMaxSize(6)`, but the I/O matrix pins `ATTENDANCE_NO_WORKING_DAYS` pre-DB. `ArrayMaxSize` was removed from the shared days DTO and replaced with a pre-RPC service guard (`assertWorkingDayRemains` in `weekly-offs.service.ts`) that throws `422 ATTENDANCE_NO_WORKING_DAYS` when all seven (pipe-validated unique, in-range) days are selected — the RPC's `PT422` and the table CHECKs remain the backstops. Re-verified live: default and override PUTs now return the pinned code; 6-day, duplicate-day and out-of-range paths unchanged. Docs/Swagger wording updated to match.

**Suite state:** `bun run test` 57 suites / 852 passed; `bunx jest --config ./test/jest-e2e.json` with real Supabase env exported 17 suites / 313 passed (14 real-DB integration probes active, 0 skipped); `bunx tsc --noEmit` 65 errors = the unchanged baseline, 0 from `src/attendance`. Every previously green suite stays green (additive change).

**Response-shape note:** the empty `GET /weekly-offs` body ships as `{ default: null, next: null, history: [] }` rather than the matrix cell's `{ default: null, overrides: [] }` — the Tasks section's two-route design (default + separate `/overrides` list) makes the merged cell's `overrides` key inapplicable; the documented shape is pinned in `docs/api-contracts.md` and covers the cell's actual contract (200, default null, never 404).

### Applied 2026-09-27 (post-user-confirmation tests)

Written after the user confirmed the live walkthrough, per the test-timing rule.

**Files** — new unit specs: `weekly-offs.service.spec.ts`, `weekly-offs.controller.spec.ts`, `holidays.service.spec.ts`, `holidays.controller.spec.ts`, `weekly-offs-response.model.spec.ts`, `notification-events.spec.ts` (registry pins: event strings, payload fields, dedupe-key shapes, per-type entries). Extended: `test/attendance.e2e-spec.ts` (weekly-off + holiday route groups: mounting, delegation, exact RPC args, 422 validation matrix via `it.each`, PT409/PT404 mappings, malformed-id 400s, PATCH `date`-key 422 + date unchanged, technician 403) and `test/integration/rls-isolation.integration.spec.ts` (7 new RPCs in the 42501 pin probed with the bare anon key and a foreign-tenant JWT; schema pins for the 3 tables; anon/foreign-JWT isolation on all three; AD-8 default lifecycle with clipping; override set/remove/idempotent re-remove; the empty-days asymmetry pinned on BOTH tables; composite-FK 23503; holiday add/past-add/duplicate PT409/rename/unknown PT404/remove; zero notifications after the whole lifecycle; impact empty + foreign-tenant PT404). Conventions follow the 15-2/15-3 suites: mock-admin chain + `expectErrorCode` for units, real DB via the jest-e2e config with Supabase env exported.

**Suite state:** `bun run test` 63 suites / 971 passed (baseline 57/852); `bunx jest --config ./test/jest-e2e.json` 17 suites / 347 passed (baseline 17/313, 0 skipped); `bunx tsc --noEmit` 65 errors = the unchanged baseline, 0 from the new spec files. The e2e/integration run's "worker process has failed to exit gracefully" note is pre-existing (realtime-probe open handles from earlier stories), not from this change.

**Bug found by the unit specs — doubled `+` in the employee phone fallback:** `readEmployeeNames` (and both RPCs of migration 03) rendered `'+91…'` as `'++91…'` because `users.country_code` is FK-enforced to `country_codes.dial_code`, which already stores the leading `+`. Fixed in `weekly-offs.service.ts` (`country_code || phone_number`, no extra prefix) and in `20260927000003_employee_name_phone_column_fix.sql` in place (uncommitted same-story file); corrected bodies re-applied live via MCP and verified (`sample_e164` = `+918528529632`, ACLs and `prosecdef` intact).

**Bug found by the real-DB probe — empty override fell back to the tenant default:** `attendance_set_weekly_off_override` shipped with the default setter's empty-clear behaviour (`if cardinality(v_days) > 0 then insert`), so `PUT overrides/:id {days: []}` returned 200 but stored nothing — the employee silently stayed on the tenant default, and "works all 7 days while the tenant has a weekly off" was inexpressible. **Precedence ruling:** the empty-days override stores a marker row — the scope-decision paragraph governs; the Boundaries "empty-days set" clause applies to the default table only (there, absence of a covering row already means all 7 days working, so no marker is needed). Fixed in `20260927000004_override_empty_days_works_all_week.sql` (recorded live via MCP `apply_migration`): the override setter now inserts unconditionally — everything else byte-identical; the default setter and the remove RPC untouched; AD-3 triple restated in-file. Migration 02's header comment corrected to document the deliberate asymmetry. The probe pins both sides: default `{}` → zero rows; override `{}` → one `[today, ∞)` `{}` marker row that wins over the still-standing default row (no fallback).

**Contract nuance pinned by tests:** `PATCH /holidays/:id` with a `date` key → `422 VALIDATION_ERROR` from the global pipe (unknown key stripped by the whitelist, then the missing-name rule fires), the controller's raw-body guard never even seeing it, and the holiday's date unchanged — asserted via status + `error_code` + a follow-up GET, not a "date not accepted" message.

### Applied 2026-09-27 (review fixes)

Fixes for the 10 accepted patches + the review follow-ups, all verified before closing the story:

**Migrations** (applied via MCP, verified in `pg_proc` — each of the six lifecycle functions now exists in exactly one signature, no `p_actor_id` overload lingering):
- `20260927000005_drop_dead_actor_id_param.sql` — decision 2: explicit `drop function` of the six old signatures (a changed signature mints a NEW pg_proc entry; the old ones would linger with their service_role grants), then re-creates all six without `p_actor_id` (bodies byte-identical to the live state, including migration 04's unconditional-insert marker-row override body); AD-3 revokes/grants restated for the new signatures.
- `20260927000006_restore_impact_epic17_comment.sql` — defer #2 fixed outright: re-creates `attendance_holiday_impact` (body byte-identical to migration 03's fixed fallback) with the EPIC 17 extension-point comment restored above the `create`; AD-3 triple restated.

**Code structure** — `src/attendance/attendance-rpc.helpers.ts` (shared `requireTenant`, `resolveTenantToday` with the hint-mapped unknown-tenant 404, `internalError`/`tenantNotFoundError` factories, HINT + `23514` constants, module logger), `src/common/utils/uuid-pattern.util.ts` (UUID pattern at one place), new `src/attendance/weekly-offs.repository.ts` (the three read helpers with corrected error logging), rewritten `weekly-offs.service.ts` (~250 lines; `assertWorkingDayRemains` and per-service `throwRpcError` kept) and `holidays.service.ts` (`listHolidays` harmonised: resolves tenant today first, unknown tenant → 404); both controllers use the shared UUID and carry corrected 404 swagger descriptions.

**Docs** — api-contracts.md: 10 contract corrections (404 lines added to GET weekly-offs / GET overrides / GET holidays / POST holidays / GET impact; "(or unknown tenant)" wording replaced by the distinct `ATTENDANCE_TENANT_NOT_FOUND`; 422 lines split by code; malformed-date 422 added to override PUT/DELETE; impact "200 — always" corrected to the empty-list pre-15-7 reality). README.md + docs/development-guide.md: `test:e2e:real` documented with the real-Node/.env requirements. package.json: `.env` existence guard in `test:e2e:real`.

**Tests updated for the dropped param + harmonised read** — unit specs (holidays: `attendance_today` queued for list calls, new unknown-tenant 404 case, `p_actor_id` assertions removed; weekly-offs: `p_actor_id` assertions removed), `test/attendance.e2e-spec.ts` (new no-tenant-owner 400 case; GET /holidays mocks queue `attendance_today`; new `{date, name}` PATCH case reaching the raw-body guard; `p_actor_id` removed from PUT/POST exact-arg assertions), `test/integration/rls-isolation.integration.spec.ts` (catalog-pin args for the six 15-5 RPCs updated to the new signatures — anon calls now expect the pin to hold on signature resolution; 15-5 real-DB probe calls drop `p_actor_id`; 15-2/15-3 probes keep theirs).

**Suite state after the fixes:** `bun run typecheck` clean; `bun run test` 63 suites / 972 passed (one up: the unknown-tenant 404 unit case); `bun run test:e2e:real` 17 suites / 349 passed (two up: the no-tenant-owner 400 and the `{date, name}` PATCH cases) — the two failures the first real-DB run exposed (leftover `p_actor_id` in two e2e exact-arg assertions and the catalog-pin sweep args) were fixed and re-run green. `bun run lint` remains at the repo-wide pre-existing baseline (~792 errors across 79 files, mostly `no-unsafe-*` on Supabase responses — untouched by this change; the lint `--fix` pass only reformatted).