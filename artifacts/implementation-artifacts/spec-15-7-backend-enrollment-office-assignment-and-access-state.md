---
title: 'Enrolment, office assignment & access state — transactional pg writes (no new RPCs), effective-dated tables, access view, me/access + onboarding endpoints'
type: 'feature'
created: '2026-09-27'
status: 'in-progress'
review_loop_iteration: 0
baseline_commit: '0c00c3f'
context:
  - '{project-root}/artifacts/planning-artifacts/epics-attendance-leave.md'
  - '{project-root}/artifacts/planning-artifacts/architecture/architecture-attendance-leave-2026-09-25/ARCHITECTURE-SPINE.md'
  - '{project-root}/artifacts/planning-artifacts/prds/prd-Fenzo-attendance-2026-09-25/prd.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-15-2-backend-attendance-module-foundation-timezone-settings-setup-gating.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-15-3-backend-offices-and-office-rules.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-15-5-backend-weekly-offs-and-holidays.md'
  - '{project-root}/artifacts/implementation-artifacts/deferred-work.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Nothing yet knows *who* is tracked or *where*: `attendance_enrolments` / `attendance_office_assignments` (AD-8) don't exist, so FR-2 (enable/disable per employee, future start dates), FR-6 (one office per tracked employee per date) and FR-3's four access states have no backing. Four shipped artefacts are parked on this story: complete-setup Gate 2 and the two archive-blocker functions lazily reference the missing tables, the holiday notification fan-out (20260927000002) is a `to_regclass`-gated branch no test can execute, and the version-tolerant 42P01 probes in `rls-isolation.integration.spec.ts` never auto-tighten. AD-17's access source of truth and the `/users/me` four-field mirror are unbuilt, as is FR-4's server-side onboarding record.

**Approach (renegotiated 2026-09-28 — no new RPCs):** The user removed the RPC layer from this story ("we will not be using RPC"). The lifecycle moves into the NestJS service over a **direct Postgres connection** (`pg` pool from `DATABASE_URL` — Supabase's documented pattern for long-lived backends; IPv6/IPv4-add-on direct, else session-mode pooler — both work with the same URL). Each enrolment write is ONE real transaction that: takes the **existing** `attendance_lock_tenant($1, false)` helper (shared lock slots with Epic 16's check-in RPCs — AD-5 intact), resolves **existing** `attendance_today($1)` (AD-7), runs the AD-8 algorithm (delete future → clip covering → insert) as plain parameterised SQL, and commits past a `DEFERRABLE INITIALLY IMMEDIATE` coverage constraint trigger — so the DB still enforces "every enrolled date covered by exactly one live-office assignment". Access state ships as a SQL **view** `attendance_access_state` (not a function): `me/access`, `/users/me` and the owner roster all read the same rows, computed in SQL, zero new RPCs. `attendance_onboarding` is a plain admin-client upsert (`ON CONFLICT DO NOTHING`). One maintenance migration amends the two **pre-existing** function bodies 15-7 owns (complete-setup Gate 2 live-office filter; archive-blocker shared predicate, ordered + deduped) — no new functions. NestJS adds owner routes under `/attendance/enrolments`, technician routes `me/access` + `me/onboarding`, and the four AD-17 fields on `/users/me`'s technician branch via an admin-client read of the view (string table name, no attendance module import). `docs/api-contracts.md` updated in the same change.

**Scope decisions locked with the user (2026-09-27/28):**
- **Spec first, then implement** — this file, reviewed by the user, precedes any migration/code (15-5 precedent).
- **No bulk RPC at all** (user: "i don't want RPC at all"; consistent with the AD-3 amendment of 2026-09-27, minimise new RPCs). FR-2's "all Employees or a selected subset" is an FE loop of the single-employee PUT; a mid-loop failure leaves earlier employees enabled — the roster shows per-employee outcome and the owner retries individually.
- **No new RPCs at all** (user, 2026-09-28: "we will not be using RPC") — lifecycle logic lives in the service over a direct pg connection inside real transactions; the only SQL called is the two pre-existing helpers (`attendance_lock_tenant`, `attendance_today`) and the two pre-existing functions this story amends (Gate 2, blockers). A dedicated story owns moving any future attendance write off RPCs; Epic 16's check-in RPC decisions are that story's to revisit.
- **Module kill switch wins: `attendance_settings.enabled = false` → `access_state = 'none'` for every employee**, regardless of enrolment rows (FR-1). History rows untouched — re-enabling restores active/history_only exactly.
- **FR-4's onboarding write ships here** (`attendance_onboarding` + first-write-wins `POST /attendance/me/onboarding`): no later backend story owns FR-4's write, and 15-10 plus AD-17's `onboardedAt` need it.
- **Single tracked predicate, defined once in this story** (in the view): enrolment covers the date AND assignment covers the date AND the assignment's office is not archived. `users.status` is deliberately excluded — the column only knows `active|invited` (no removal feature exists), and FR-2 explicitly allows enrolling an invited technician who has never logged in. FR-28's carve-out arrives with the removal feature.
- **Archived office targets rejected with `409 ATTENDANCE_OFFICE_ARCHIVED`** (state conflict) on enable and reassign; unknown office stays `404 ATTENDANCE_OFFICE_NOT_FOUND` (code exists).

**New infrastructure this decision introduces (deployment prerequisites):**
- `DATABASE_URL` secret (direct `db.<ref>.supabase.co:5432/postgres`, or `aws-<n>-<region>.pooler.supabase.com:5432/postgres` session pooler when the network is IPv4-only) in local `.env` and Render. SSL required (`sslmode=require` at minimum). The pg pool fails fast (boot error) when unset.
- Supabase MCP still applies all migrations (repo rule unchanged); the runtime pg pool is application code, not a migration tool.

## Boundaries & Constraints

**Always:**
- Migrations start at `20260927000007` (latest in-repo `20260927000006`; re-verify against MCP `list_migrations` before applying), one concern per file, applied via Supabase MCP.
- All three tables: RLS enabled, **no policies** (deny-by-default; the admin client and the pg pool's service credentials are the only writers), `tenant_id NOT NULL` where applicable, `update_updated_at_column` triggers, composite-FK hardening (`users.UNIQUE (id, tenant_id)` exists since 15-5; offices carry their tenant pairing).
- AD-8 on both lifecycle tables: `valid DATERANGE NOT NULL CHECK (NOT isempty(valid))` + `EXCLUDE USING gist (<owner key> WITH =, valid WITH &&)`; `attendance_enrolments (employee_id, valid, enabled_at timestamptz NOT NULL DEFAULT now())`; `attendance_office_assignments (employee_id, office_id, valid)`.
- The coverage invariant is a `CONSTRAINT TRIGGER … DEFERRABLE INITIALLY IMMEDIATE` on both tables: every enrolled date has exactly one **live-office** assignment (EXCLUDE gives at-most-one; the trigger at-least-one), and no assigned date falls outside an enrolment. Valid only because every write path is a single pg transaction — a violation surfaces as `23514` at COMMIT → PT422 `ATTENDANCE_ASSIGNMENT_GAP`.
- The AD-8 write algorithm verbatim, in the service, inside one transaction: `effective_from = greatest(p_from, attendance_today)`; delete the owner's ranges starting on/after `effective_from`; clip the covering range's upper bound; insert `[effective_from, ∞)`. Disable = same algorithm, final insert omitted, run against both tables. `greatest()` clamp, not a 422. Enable co-writes enrolment + assignment atomically; reassign writes assignments only and requires an enrolment covering the effective date (422 `ATTENDANCE_ASSIGNMENT_NOT_ENROLLED` otherwise).
- Locks: every enrolment write opens its transaction with `SELECT public.attendance_lock_tenant($1, false)` (shared tenant lock — AD-5; single-employee scope). Existing helpers only; no new lock SQL.
- Access state derives only in the `attendance_access_state` view: `none` (never tracked, or kill switch off), `upcoming` (next period starts in the future), `active` (enrolment covers today), `history_only` (past enrolments only) + `attendance_enabled`, `attendance_start_date` (covering or next period start), `onboarded_at`, `office_id`/`office_name` of the live covering assignment. Views: `REVOKE SELECT … FROM anon, authenticated, public` (admin/pg-pool only).
- Technician identity for `me/*` routes comes **only** from `@CurrentUser()`; owner routes `@Roles(Role.OWNER)`.
- pg pool: small app-side pool (max ~5), `ssl: require`, parameterised queries only (no string interpolation), `search_path = public` pinned per transaction; every transaction COMMITs or ROLLBACKs in a `try/finally`.
- Update `docs/api-contracts.md` in the same change (Enrolments section after Holidays, `me/access` + `me/onboarding`, `/users/me` four-field note, Endpoints tree).

**Ask First:**
- If `DATABASE_URL` cannot be provisioned for Render before deploy, the pg-backed routes must not ship — confirm the deploy plan.
- If tightening the parked 42P01 probes requires restructuring pre-existing probe blocks beyond the four noted sites, confirm before renumbering.

**Never:**
- No new stored procedures/functions (user decision 2026-09-28) — nothing new is callable via PostgREST. Two carve-outs, neither an RPC surface: the coverage constraint trigger's internal helper function (triggers cannot be invoked, carry no EXECUTE grant, and AD-8 mandates the trigger), and the two named pre-existing function bodies this story re-creates (Gate 2, blockers) with unchanged signatures.
- No `attendance_records`, no `attendance_day_context`, no FR-2 grace evaluation here (Epic 16 owns AD-22; this story only stores `enabled_at` for it).
- No leave tables, no FR-28 removal feature, no reminders, no FE changes (15-8/15-9/15-10 own the wizard, roster UI and onboarding screens).
- No employee-side reads beyond `me/access` + `me/onboarding` (weekly-off/holiday visibility arrives with 15-10/19-6).
- No idempotency keys/interceptor on these routes (AD-6 covers check-in/out/leave only; owner writes are single-transaction and AD-8-convergent; `me/onboarding` is first-write-wins).
- No per-employee timing overrides (PRD: rules are office-level only).
- No raw `service_role` JWT over PostgREST for these writes — they go over the pg pool with parameterised SQL; the pool credential is the same DB role the admin client's service key maps to (hardening follow-up: a dedicated least-privilege role, recorded in deferred-work).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Migration applies to live DB | no enrolment tables | 3 tables + constraint trigger + RLS/no-policies + exclusions + 1 view (anon/authenticated revoked) verified live; Gate 2 / blockers / holiday fan-out all executable | — |
| Owner enables an employee for today | `PUT /enrolments/:employeeId { officeId, startDate: today }` | One transaction: enrolment + assignment `[today, ∞)`, `enabled_at = now()`; 200 `{ employeeId, accessState: 'active', attendanceStartDate, officeId }` | Unknown/non-member employee → 404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`; unknown office → 404 `ATTENDANCE_OFFICE_NOT_FOUND`; archived office → 409 `ATTENDANCE_OFFICE_ARCHIVED` |
| Owner enables an invited technician from 1 Nov | future `startDate`, user never logged in | Rows effective 1 Nov; `me/access` → `upcoming` + `attendanceStartDate = 1 Nov`; before it: no attendance UI, no owner not-checked-in appearances (Epic 18/19 read-side) | — |
| Owner changes a future start date | enable again with new date while `upcoming` | Future ranges deleted/clip + insert per AD-8 — no zombie ranges | — |
| Owner cancels a future start | `DELETE /enrolments/:employeeId` (effective today, future-only enrolment) | Clip+delete only: enrolment and assignment vanish entirely; access → `none`; idempotent replay → 200 unchanged | — |
| Owner disables an active employee | `DELETE /enrolments/:employeeId` | Both covering ranges clipped at today; history kept read-only; access → `history_only` | — |
| Owner re-enables after a gap | enable again | New period `[today, ∞)` with fresh `enabled_at`; the gap reads Not tracked (16-1) | — |
| Owner reassigns office effective today | `PUT /enrolments/:employeeId/office { officeId }` | Covering assignment clipped, new `[today, ∞)`; enrolment untouched | No enrolment covering the effective date → 422 `ATTENDANCE_ASSIGNMENT_NOT_ENROLLED`; office errors as above |
| Reassignment when employee checked in today | `attendance_records` exists (post-16-1) with today's row | The service's guarded probe forces `effective_from = tomorrow` (FR-6); pre-16 the probe finds nothing and the chosen date applies | — |
| Coverage trigger backstop | any write leaving an enrolled date uncovered | Transaction rejected at COMMIT | `23514` → 422 `ATTENDANCE_ASSIGNMENT_GAP` |
| Owner "enables all" from the FE | sequential `PUT /enrolments/:employeeId` per employee (no bulk — user decision) | Each commits independently; roster shows per-employee outcome; failures retried individually | Per-employee errors as above |
| Technician reads access | `GET /me/access` with valid JWT | `{ attendanceEnabled, attendanceAccess, attendanceStartDate, onboardedAt }` from the view; kill switch off → `none` | id from `@CurrentUser()` only — cross-tenant impossible |
| Technician completes onboarding | `POST /me/onboarding` (first call) | `attendance_onboarding` row; `onboardedAt` set; replay → 200 same value, no second write | — |
| First load mirror | `GET /users/me` (technician branch) | Same four fields, admin-client read of the view (string table name — no attendance import); owner branch unchanged | View read failure → profile 500s fail-loud (no silent nulls) |
| Owner reads the roster | `GET /enrolments` | Per-employee `{ employeeId, employeeName, phone, accessState, attendanceStartDate, enabledAt, officeId, officeName }` — view rows joined to users, state never computed in TS | Empty → 200 `[]` |
| Complete-setup Gate 2, reconciled | enrolment + assignment + **live** office exist | Completes; an archived-only office no longer satisfies the gate | Still `422 ATTENDANCE_SETUP_INCOMPLETE` without a tracked employee |
| Archive an office with tracked assignees | `attendance_archive_office` | Blocked; blockers RPC returns ordered, deduped list (single shared predicate — copy-paste gone) | After all assignees disabled → archive succeeds |
| Holiday fan-out, now executable | enrol a tracked employee, `attendance_add_holiday` (future date) | `attendance.holiday_added` notification row(s) in-transaction matching `ATTENDANCE_NOTIFICATION_EVENT_REGISTRY`; `attendance_remove_holiday` → `holiday_removed` | Registry drift fails the journey probe |
| `DATABASE_URL` unset / pool fails | boot or first pg use | Fail-fast boot error naming the env var (no silent HTTP 500s from a dead pool) | — |
| Anon/authenticated touches the view or tables | Direct PostgREST read | Denied | 42501/PGRST (catalog probe pins this) |
| Technician calls owner enrolment routes | JWT role ≠ owner | 403 FORBIDDEN on every handler | — |

</frozen-after-approval>

## Change Log

- **2026-09-28 (real-DB journey probe):** `test/integration/attendance-enrolments.integration.spec.ts` added (11 probes, `DATABASE_URL`-gated, self-contained fixtures, FK-safe cleanup) — the full flow against the REAL DB: access states ×4 (none → kill-switch none → active → upcoming → history_only), enable/reassign/disable/re-enable through the shipped repository SQL, complete-setup Gate 2 (negative + positive), the holiday fan-out executable-verified against `ATTENDANCE_NOTIFICATION_EVENT_REGISTRY` (closes the Spec-15-5 deferred item), coverage-guard COMMIT rejection with the GAP hint, and the archive-blocker → archive → re-enable-after-archive regression. Probe authoring found one more guard hole — the day-sum comparison cannot detect gaps once both sides are infinite (a `[today,∞)` enrolment with only a `[next-month,∞)` leg summed to ∞ = ∞) — fixed with **exact endpoint chaining** (first leg starts at the period start, each next leg starts where the previous ended, chain reaches the period end; sentinel-normalised), applied as corrective `fix_15_7_review_guard_chaining` and folded into the migration file. Full real-DB suite: 18/18 suites, **374 passed** (includes the 11 new probes); mocked e2e 17/17 (348) and unit 66/66 (1003) stay green.

- **2026-09-28 (BMAD code review):** run via the on-disk `bmad-code-review` workflow (manual fallback — 4 layers × 3 chunks = 12 subagents; **4 layers rate-limited** (verification-gap A/B, blind-hunter B, acceptance-auditor B) and recorded per the workflow's failed-layers rule; 8 completed). ~55 raw findings triaged → 0 decisions needed, **13 patches applied** (below), 6 defers, ~14 dismissed. Frozen-text supersessions recorded: the coverage trigger ships **INITIALLY DEFERRED** (the frozen "INITIALLY IMMEDIATE" line was internally inconsistent with the two-statement enable — Change Log above), and migration 2 covers the **holiday trio** as well as Gate 2 + blockers (sanctioned by AC-5's executable-verification requirement). API response shapes use `attendanceAccess`/`enabledAt`/`officeId`/`officeName` (spec matrix's `accessState` naming superseded — AD-17 field alignment). Deferred-work items closed by this story's reconciliations are marked in `deferred-work.md` only after the real-DB journey probe runs.

### Review Findings

BMAD code review 2026-09-28 (8 of 12 layers completed; findings source-tagged blind-hunter / edge-case-hunter / verification-gap / acceptance-auditor per chunk). Acceptance-audit verdict after patches: ACs met on the corrected bodies; suites re-run green (66/66 unit, 1003 tests; 17/17 e2e, 348).

**Patches applied:**
- [CRITICAL] **Holiday overload resurrection** — migration 2 re-created the dead `p_actor_id` holiday signatures (dropped by 20260927000005) while the LIVE no-actor signatures the services call kept their stale dormant bodies: the fan-out reconciliation would never execute on the real path. Applied: corrective `fix_15_7_review_criticals` drops the phantom overloads, re-creates the live signatures with reconciled bodies, re-anchors grants; catalog-verified single signatures + live-execution probe.
- [CRITICAL] **Display-name regression** — blockers + impact re-created with pre-split `coalesce(u.name, u.phone)` → 42703 at first call. Restored the 20260927000003 expression (`nullif(name,'') ‖ country_code||phone_number`); live-execution probe green.
- [HIGH] **Archive blocker NULL-upper** — `upper(a.valid) > today` is NULL for unbounded (active/upcoming) assignments on PG17, so offices with actively assigned employees were archivable. Coalesced to `'infinity'::date`.
- [HIGH] **Coverage guard vs archived history** — live-office liveness over the employee's ENTIRE history permanently locked the lifecycle (23514) once any past office was archived. Liveness now scoped to current-or-future periods; closed history requires coverage by any assignment.
- [HIGH] **`ATTENDANCE_ASSIGNMENT_GAP` 422 never produced** — the service mapped only the tenant hint; a COMMIT-time trigger rejection surfaced as a raw 500 while docs promised 422. Service now maps it; unit case added.
- [HIGH] **Missing exclusive employee lock** — writes took only the shared tenant lock; two concurrent writes for one employee could interleave. Now shared-tenant + exclusive-employee (AD-5) per write.
- Kill-switch asymmetry: holiday fan-outs additionally gated on `attendance_settings.enabled`.
- View hardening: `security_invoker = true` + tenant-qualified rows only.
- Open-end convention enforced: CHECKs ban an explicit `'infinity'` upper (the guard sentinel assumes NULL = open); `office_id` index for blocker/fan-out joins; inert anon/authenticated grants revoked on the three tables; guard gets `search_path` + EXECUTE revoked.
- pg-path timestamps normalised to ISO-8601 (AD-7) — caught by the live walkthrough, not the review.
- `withTransaction` gains a statement timeout; daterange parser rejects empty lower bounds; `attendance_today` result format-validated.
- e2e/unit patches: DELETE asserts the post-disable `history_only` state; onboarding replay case; reassign happy + 422 `ATTENDANCE_ASSIGNMENT_NOT_ENROLLED`; roster 200; 400 no-tenant; 401; GAP mapping unit case; describe-title drift; jest.env empty-string guard.
- api-contracts corrections: 403s on `me/access`/`me/onboarding`, DEFERRED wording, `/users/me` attendance note, DELETE state semantics, onboarding gating note.

**Deferred:**
- Real-DB journey probe + rls-isolation probe tightening — already this story's remaining task; needs the real-DB run (the corrective's live-execution probe covers the previously-dormant functions' first execution).
- `/users/me` populated-view e2e (unit pins the mapping; live walkthrough verified it).
- Walkthrough/prereq script hardening (JWT guard, exit codes, 6543 detection) — dev utilities, not shipped code.
- `upcoming` period's `enabled_at` in the view (16-1's AD-22 reads the tables directly for the grace rule).
- DB-enforced onboarding first-write-wins (NestJS is the sanctioned writer — holidays-naming precedent).
- Tenant-delete RESTRICT chain (FR-28's removal feature owns deletion semantics; history-kept makes RESTRICT the safer default).

**Dismissed (~14):** today-boundary holiday notifications (spec-frozen future-only, 15-5 locked decision); Gate 2's dropped `enabled_at is not null` (column is NOT NULL); migration-2 file name/scope; frozen-matrix response-shape names (superseded, recorded above); POST/DELETE empty-body 400s (walkthrough-script artifact, not an API behaviour); `e.valid @> lower(a.valid)` enrolment-side liveness in blockers (single-source predicate retained); roster pagination (PRD tenant scale); view `select *` in service reads (typed mapping); and others verified false positives on read (e.g. `u.phone` substring greps matching `u.phone_number`).

- **2026-09-28 (applied + live-verified):** both migrations applied via MCP; corrective applies brought the live DB to the repo file state: **fix_15_7_view_grants** (Supabase default privileges left inert write grants on the view — REVOKE ALL, service_role SELECT only), **fix_15_7_coverage_guard_unbounded_span** (upper() of an unbounded daterange is NULL on PG17 and `'infinity'::date - date` raises 22008 — the day-span check now uses a `9999-12-31` finite sentinel; the original silently passed unbounded enrolments, the common case), **fix_15_7_coverage_trigger_deferred** (INITIALLY IMMEDIATE rejected the first statement of every co-written enable — the coverage check runs at COMMIT, INITIALLY DEFERRED). Live probes (throwaway fixtures, zero residue): unpaired unbounded/bounded enrolment → 23514 `ATTENDANCE_ASSIGNMENT_GAP`; paired enable + split reassignment across two offices → commits; mid-transaction gap → aborts at COMMIT with full rollback; assignment outside any enrolment → 23514; view reads `none` + `attendance_enabled=false` for enrolled employees while the kill switch is off (locked decision honoured); Gate 2/blockers/holiday functions carry the live-office predicate; no public EXECUTE on any attendance function.

- **2026-09-28 (human renegotiation):** original draft shipped the lifecycle as seven SECURITY DEFINER RPCs (15-2/15-3/15-5 precedent). User removed the RPC layer ("we will not be using RPC") after the bulk-RPC decision; approach reworked to transactional service-side writes over a direct pg connection + access-state view. Consequences recorded: coverage constraint trigger stays viable (DEFERRABLE, commit-time) only because writes are single transactions; `attendance_access` becomes a view (AD-17's "one source, light endpoint" intact — the function name survives as the view's source of truth); `DATABASE_URL` becomes a deployment prerequisite; a least-privilege pg role and the Epic 16 RPC-vs-pg decision are follow-ups. E2E coverage for the new routes added to this story's test scope per user instruction (2026-09-28).

## Code Map

Investigation evidence (2026-09-27; paths relative to `fenzit-be/`):

- **Migration numbering** — latest in-repo `20260927000006_restore_impact_epic17_comment.sql`; re-verify via MCP `list_migrations`, start at `20260927000007`.
- **AD-8 algorithm precedent (to mirror in TS)** — `20260927000002_rpc_weekly_off_and_holiday_lifecycle.sql` (delete-future → clip-covering → insert; clip-without-insert for disable).
- **Composite-FK hardening** — `users.UNIQUE (id, tenant_id)` (15-5, `20260927000001`); child FKs copy `(employee_id, tenant_id)`. `btree_gist` enabled since `20260926000005`.
- **Existing helpers the service calls (no new SQL objects)** — `attendance_lock_tenant` / `attendance_today` in `20260926000003`.
- **Dormant predicates this story reconciles:** complete-setup Gate 2 (`20260926000003_attendance_helpers_and_complete_setup.sql:114-135` — no `archived_at` filter; deferred-work Spec-15-2 item); blocker functions (`20260926000006:154-250` — copy-pasted predicate, unbounded/unordered; deferred-work Spec-15-3 item); holiday fan-out branch (`20260927000002:272-289,375-394` — zero executable coverage; deferred-work Spec-15-5 item: journey probe asserts persisted rows against `ATTENDANCE_NOTIFICATION_EVENT_REGISTRY`); 42P01 probe tightening (`test/integration/rls-isolation.integration.spec.ts:995-1035, 1706-1710, 2082-2109`).
- **Registry** — `src/attendance/notification-events.ts`; no new event types in this story (enrolment emits no notifications).
- **Error codes** — append under `// Attendance (Epic 15)` in `src/common/enums/error-code.enum.ts` (ends at `ATTENDANCE_HOLIDAY_NOT_FOUND`): `ATTENDANCE_OFFICE_ARCHIVED`, `ATTENDANCE_ASSIGNMENT_GAP`, `ATTENDANCE_ASSIGNMENT_NOT_ENROLLED`.
- **pg infrastructure** — `src/common/factories/supabase-client.factory.ts` is the pattern to mirror: a `PgPoolFactory` (`pg.Pool` from `DATABASE_URL`, ssl require, max 5) + a `withTransaction(helper)` wrapper (BEGIN → lock/today → work → COMMIT/ROLLBACK in finally). Registered on `SupabaseModule`'s replacement? No — a small `PgModule` imported by `AttendanceModule` only (no other module grows pg access in this story).
- **Module layout** — `enrolments.controller.ts` (`@Controller('attendance/enrolments')`, owner) + `enrolments.service.ts` + `enrolments.repository.ts` (pg SQL) + `dto/enrolment.dto.ts` + `enrolments-response.model.ts`; `me.controller.ts` (`@Controller('attendance/me')`, technician) reads the view via the admin client; register all in `attendance.module.ts`. Every file ≤ ~300 lines.
- **`/users/me`** — technician branch of `UsersService.getProfile` (`src/users/users.service.ts`): add the four fields from `createAdmin().from('attendance_access_state')…eq('user_id', userId)` — string table name, **no import from `src/attendance/**`**. Swagger on `users.controller.ts` updated.
- **Integration probe infra** — `RPC_FUNCTIONS` map unchanged (no new functions); schema pins gain the 3 tables + the view; the four parked-probe sites tighten to post-15-7 behaviour; new real-DB journey probe: enrol → access states ×4 → reassign → disable → re-enable → holiday fan-out rows vs registry → Gate 2 + archive-blocker behaviour. `test/attendance.e2e-spec.ts` extends with enrolment + me routes (mocked pg pool + admin client: mounting, 403 technician, 400 no-tenant, 422 validation, happy paths).
- **api-contracts.md** — "Attendance enrolments (Epic 15, Story 15-7, owner only)" after Holidays; technician `me/access` + `me/onboarding` subsection; `/users/me` field note; Endpoints tree.

## Tasks & Acceptance

**Execution:**
- [ ] `supabase/migrations/20260927000007_attendance_enrolment_tables.sql` — 3 tables (AD-8 exclusions, FKs, RLS no-policies, updated_at triggers), the DEFERRABLE coverage constraint trigger, `attendance_access_state` view (revokes), all in one file. Apply via MCP; verify live.
- [ ] `supabase/migrations/20260927000008_reconcile_gates_and_blockers.sql` — re-create `attendance_complete_setup` (Gate 2 + live-office filter), `attendance_archive_office` + `attendance_office_archive_blockers` (shared predicate, ordered deduped list); old signatures dropped explicitly (20260927000005 precedent); no new functions.
- [ ] `src/common/enums/error-code.enum.ts` — three new codes.
- [ ] pg infra: `src/infrastructure/pg/pg.module.ts` + `pg-pool.factory.ts` + `with-transaction.ts` (fail-fast on missing `DATABASE_URL`; `.env.example` + README rows).
- [ ] `src/attendance/enrolments.repository.ts` (parameterised SQL) + `enrolments.{controller,service}.ts` + `dto/enrolment.dto.ts` + `enrolments-response.model.ts` — `GET /enrolments`, `PUT /enrolments/:employeeId`, `PUT /enrolments/:employeeId/office`, `DELETE /enrolments/:employeeId`.
- [ ] `src/attendance/me.controller.ts` (+ service) — `GET /attendance/me/access`, `POST /attendance/me/onboarding` (admin client: view read + upsert ignoreDuplicates).
- [ ] `src/users/users.service.ts` + `users.controller.ts` — four AD-17 fields on the technician branch.
- [ ] `docs/api-contracts.md` + Swagger blocks in the same change.
- [ ] Tests (e2e included in-story per user instruction 2026-09-28): enrolments service/repository/controller + me + pure-model unit specs; `test/attendance.e2e-spec.ts` extensions (mounting, 403, 400, 422, happy paths with mocked pool); `rls-isolation.integration.spec.ts` — schema pins, four probe sites tightened, full journey probe incl. holiday fan-out vs registry (closes the Spec-15-5 deferred item). Real-DB walkthrough by the user precedes any real-DB probe assertions beyond the journey spec.

**Acceptance Criteria:**
- Given the migrations applied, when the catalog is inspected, then all three tables + the view exist with RLS enabled/no policies (view: anon/authenticated revoked), both exclusions + the coverage constraint trigger exist, and the only functions touched are the trigger helper plus the pre-existing bodies re-created with identical signatures.
- Given an owner enabling an employee (today or future date), when the PUT runs, then one transaction creates enrolment + assignment per AD-8 with `enabled_at` stored; dates before the start are untracked; changing or cancelling a future start leaves no zombie ranges; disable keeps history read-only and re-enable starts a new period.
- Given a tracked employee, when offices change, then exactly one live office covers every enrolled date (trigger backstop at COMMIT), reassignment honours FR-6 (today, or tomorrow once `attendance_records` exists and today has a check-in), and an archived office is refused.
- Given `GET /me/access` and the `/users/me` mirror, when an employee's enrolment changes, then both report the same `none | upcoming | active | history_only` plus `attendanceStartDate` and `onboardedAt`, with the kill switch forcing `none`.
- Given the parked artefacts, when this story merges, then Gate 2 requires a live office, archive blockers are ordered/deduped via one shared predicate, the holiday fan-out is executable-verified against the registry, and every formerly version-tolerant probe asserts the real post-15-7 behaviour.
- Given all previously green suites, then every one stays green (additive; the two re-created functions change no contract surfaced before 15-7).
