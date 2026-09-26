---
title: 'Offices & office rules — tables, lifecycle RPCs & office routes'
type: 'feature'
created: '2026-09-26'
status: 'in-progress'
review_loop_iteration: 0
baseline_commit: 'bae054e'
context:
  - '{project-root}/artifacts/planning-artifacts/epics-attendance-leave.md'
  - '{project-root}/artifacts/planning-artifacts/architecture/architecture-attendance-leave-2026-09-25/ARCHITECTURE-SPINE.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-15-2-backend-attendance-module-foundation-timezone-settings-setup-gating.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Epic 16's check-in/out has nothing to validate against — there are no Offices, no effective-dated timing/hours rules, and no archive path. `attendance_complete_setup` (15-2) references an `attendance_offices` table that does not exist yet, so its first gate can never pass.

**Approach:** One migration enables `btree_gist` and creates `attendance_offices` (name unique per tenant, pin lat/lng, radius 50–1000 m, `archived_at` — never deleted, AD-25) and `attendance_office_rules` (effective-dated `valid daterange`, `EXCLUDE USING gist (office_id WITH =, valid WITH &&)` non-overlap — AD-8). A second migration creates four SECURITY DEFINER RPCs: `attendance_create_office` (inserts office + initial rule valid `[today, ∞)` — two row-sets, one RPC per AD-3), `attendance_update_office_rules` (the shared AD-8 algorithm, `effective_from = tomorrow`), `attendance_archive_office` (exclusive tenant lock, blocked by tracked employees with current/future assignments — AD-25; blockers table arrives in 15-7, so the body is lazy-compiled PL/pgSQL, the sanctioned `attendance_complete_setup` precedent), and the read/preview function `attendance_office_archive_blockers` (AD-24). `btree_gist` + tables + RPCs are applied via Supabase MCP. A `src/attendance/` extension exposes `/attendance/offices` routes — list/detail (admin-client reads with the rule valid on today, plus a pending next rule), create, one PATCH (profile fields → guarded single-row UPDATE; rules fields → the rules RPC, per the user's one-route decision), archive, and the archive-blockers preview GET. `docs/api-contracts.md` gains the Offices section in the same change.

**Scope decisions locked with the user (2026-09-26):**
- The archive RPC + blockers preview ship **now, lazy-compiled** against the 15-7 tables (enrolments/assignments do not exist yet; calls fail loud until 15-7) — same precedent as `attendance_complete_setup` in 15-2. **[Amended same day, 2026-09-26 — see Resolution]**
- Editing is **one PATCH route** (`PATCH /attendance/offices/:id`) that internally splits: name/pin/radius → guarded UPDATE; timing/hours → the effective-dated RPC.
- Office names are **unique per tenant** — `UNIQUE (tenant_id, lower(name))`.

## Boundaries & Constraints

**Always:**
- Migrations start at `20260926000005` (latest applied today is `20260926000004`), one concern per file, applied via Supabase MCP.
- Every new function in the same file as its creation: `SECURITY DEFINER SET search_path = public` + `REVOKE EXECUTE … FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE … TO service_role` (AD-3 triple, 15-2 pattern).
- Both tables: RLS enabled, **no policies** (deny-by-default, the 15-2 review decision) — every read/write goes through the NestJS admin client with an explicit `tenant_id` filter; `tenant_id NOT NULL` on every row (consistency conventions).
- `attendance_office_rules` carries `valid daterange NOT NULL CHECK (NOT isempty(valid))` + `EXCLUDE USING gist (office_id WITH =, valid WITH &&)`; range checks as CHECK constraints (NFR-4): radius 50–1000, late cut-off 0–120, full/half-day hours > 0, half < full, `end_time > start_time` (same-day TIME — no overnight offices).
- DB thresholds are the authority (50–1000 m, 0–120 min); TS mirrors them for DTO validation only.
- Rules edits run the AD-8 algorithm exactly: `effective_from = attendance_today(p_tenant_id) + 1` (tomorrow); delete the office's ranges starting on/after `effective_from`; clip the covering range's upper bound to `effective_from`; insert the new range `[effective_from, ∞)`. Past dates keep the rule active on that date.
- Exclusive tenant lock (`attendance_lock_tenant(p_tenant_id, true)`) inside `attendance_update_office_rules` and `attendance_archive_office` (archive is AD-25-mandated; rules edits mutate the range set).
- Archive sets `archived_at` and is never a delete (AD-25).
- Update `docs/api-contracts.md` in the same change (Offices section after the existing Attendance setup section, plus the Endpoints tree).

**Ask First:**
- If the non-overlap exclusion or the effective-dating algorithm cannot be expressed as specified (e.g. PostgREST cannot filter `daterange` containment for reads), HALT and confirm the fallback before deviating.
- If archive blockers turn out to be computable without the 15-7 tables, confirm before changing the lazy-compile plan.

**Never:**
- No enrolments, assignments, weekly-off or holidays tables in this story (15-5 / 15-7 own those).
- No effective-dating on the office row itself — pin and radius live on `attendance_offices` and are plain columns (AD-8 adopted wording).
- No idempotency interceptor on office routes (AD-6 excludes it; create is FE-guarded, PATCH and archive are naturally idempotent or lock-serialised).
- No `getIstDayRange` changes — "today" comes only from `attendance_today(p_tenant_id)`.
- No office deletion or unarchive route (PRD FR-5 scope: create/edit/archive only).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Migration applies to live DB | no attendance offices tables, `btree_gist` absent | Extension enabled; both tables created, RLS enabled, no policies, updated_at triggers attached | — |
| Owner creates an office with valid payload | name unique, radius 100, 10:00–18:00, cutoff 15, 8/4 h | Office row + rules row `valid [today, ∞)`; 201 | Duplicate name → 409 `ATTENDANCE_OFFICE_NAME_TAKEN`; DB CHECK violation → 422 mapped from `23514`; exclusion violation → 500 (algorithm bug, fail loud) |
| Owner creates an office with a taken name | name case-insensitively equal to another office in the tenant | Nothing saved | 409 `ATTENDANCE_OFFICE_NAME_TAKEN` (unique index `23514`/`23P01` never surfaces raw) |
| Owner creates an office with out-of-range values | radius 40, or cutoff 200, half ≥ full | Rejected before the DB | 422 `VALIDATION_ERROR` (class-validator mirrors) |
| Owner edits profile fields only | `{ name?, latitude?, longitude?, radiusM? }` | Guarded UPDATE with tenant + not-archived filter; 200 | Unknown id / archived → 404 `ATTENDANCE_OFFICE_NOT_FOUND`; name taken → 409 |
| Owner edits rules | `{ startTime, endTime, lateCutoffMinutes, fullDayHours, halfDayHours }` | RPC: tomorrow-clipped ranges + new open range; today/past unchanged; 200 | Unknown id → 404; CHECK violation → 422; unknown tenant → `ATTENDANCE_TENANT_NOT_FOUND` from `attendance_today` (fail loud) |
| Owner edits rules twice same day | second edit same day | First edit's `[tomorrow, ∞)` range is deleted (starts on/after effective_from) and replaced — no overlap, no zombie future rules | — |
| Owner edits profile + rules together | both field groups present | Profile UPDATE then rules RPC, sequentially; 200 | Any failure aborts the response with its own status; partial state possible only across the two writes (documented; no transaction across admin client + rpc) |
| Owner archives an office with no tracked employees | assignments empty (pre-15-7) | RPC sets `archived_at`; 204 no-content (amended 2026-09-26 code review: shipped 204 with docs + tests consistent; 200 was the draft value) (body compiles lazily — blocker probe fails loud with 42P01 only if the 15-7 tables are touched; gate order keeps the blocker check first, so pre-15-7 calls fail loud at the blocker query) | Blockers found → 409 `ATTENDANCE_OFFICE_ARCHIVE_BLOCKED` with blocker list built from the preview function |
| Owner fetches archive blockers | `GET /offices/:id/archive/preview` | Read function output: `{ officeId, blockers: [{ employeeId, employeeName }] }`; empty list pre-15-7 (or fail loud until tables exist — pinned by the integration probe) | Unknown id → 404 |
| Owner lists offices | `GET /offices?includeArchived=false` (default) | Offices each with the rule whose `valid` contains today (via `attendance_today`) and an optional future rule; camelCase, times `HH:mm`, dates `YYYY-MM-DD` | Empty list → 200 `[]` (never 404) |
| Anon/authenticated calls any office function | Direct PostgREST rpc | Function not executable | `42501` (catalog probe pins this) |
| Owner calls any office route without a tracked setup | setup not completed | Routes work (wizard writes real rows mid-setup, AD-25) — no gating beyond roles | — |

</frozen-after-approval>

## Code Map

Investigation evidence (2026-09-26; paths relative to `fenzit-be/`; entries carried forward from the verified 15-2 code map are marked ⟨15-2⟩):

- **Migration numbering** — latest applied is `20260926000004_rpc_attendance_start_setup.sql`; this story starts at `20260926000005`.
- **`btree_gist` absent** — confirmed live during 15-2 planning; this story's first migration enables it (`CREATE EXTENSION IF NOT EXISTS btree_gist`).
- **`attendance_complete_setup` references the missing offices table** — `supabase/migrations/20260926000003_attendance_helpers_and_complete_setup.sql` (PL/pgSQL, lazy body); this story's tables make gate 1 live. 15-2 review defer: gate 2 (enrolments/users.status) stays deferred to 15-7.
- **PTxxx raise + HINT pattern** — `supabase/migrations/20260920000005_rpc_claim_report_request.sql` ⟨15-2⟩; error codes appended under `// Attendance (Epic 15)` in `src/common/enums/error-code.enum.ts`.
- **AD-3 grant pattern** — `supabase/migrations/20260925000003_default_privileges_no_public_execute.sql:42-82` ⟨15-2⟩; per-function triple in each new migration.
- **Advisory lock helpers already exist** — `attendance_lock_tenant(p_tenant_id, p_exclusive)` / `attendance_lock_employee(p_employee_id)` in `20260926000003`; `attendance_today(p_tenant_id)` fail-loud (PT404 on unknown tenant) after the 15-2 review fixes. This story calls all three from its RPCs — no new helpers.
- **RLS no-policies table precedent** — `20260926000002_attendance_foundation_tables.sql` (the review-decision shape: `ALTER TABLE … ENABLE ROW LEVEL SECURITY;` and nothing else) + `update_updated_at_column` trigger reuse.
- **Admin client factory** — `src/common/factories/supabase-client.factory.ts:35-43` ⟨15-2⟩; the sanctioned path for all office reads/writes.
- **Existing attendance module** — `src/attendance/attendance.module.ts|controller.ts|service.ts` + `dto/` + `attendance-response.model.ts` (15-2): controller is `@Controller('attendance/setup')`; this story adds a sibling `@Controller('attendance/offices')` in the same module, reusing `SupabaseModule` registration. The 15-2 service pattern to mirror: `requireTenant` guard first (400 `VALIDATION_ERROR` without a tenant claim), PTxxx→HTTP mapping constants, camelCase row mapping.
- **Controller conventions** — `src/reports/reports.controller.ts:30-119` ⟨15-2⟩: `:id` routes below parameterless `@Get()`, `@Roles(Role.OWNER)` per route, `@HttpCode`, Swagger blocks; ValidationPipe 422 (`src/common/validation-pipe-options.ts`); GlobalExceptionFilter renders `{ statusCode, error_code, message, ...extra }` (`src/common/filters/global-exception.filter.ts:93-101`) — `extra` carries the blocker list on 409 archive responses.
- **Guarded write precedent** — `src/reports/reports.service.ts:88-98` (explicit tenant_id from JWT) and `getOwnRowOrThrow` (tenant-filtered read, PGRST116→404) ⟨15-2⟩; the profile-edit UPDATE follows the 15-2 `saveStep` guarded-UPDATE shape (zero rows → 404).
- **PostgREST range containment — verified live, deviation taken (2026-09-26):** the pre-approved fallback is in force. supab-js `.filter('valid', 'cs', '[<today>,)')` parses but returns wrong/empty results, and element filters (`sr`) are rejected outright — PostgREST range operators only accept full range literals. The service therefore fetches each office's (small) rules history with a plain `.in('office_id', …)` and picks current/next with the pure model functions `pickCurrentRule`/`pickNextRule` against `attendance_today()`, which remains the sole source of "today" (AD-7).
- **Integration probe infra** — `test/integration/rls-isolation.integration.spec.ts`: `RPC_FUNCTIONS` map (~L918) gains the four new functions (anon + authenticated → `42501`); schema-pin pattern (~L1298) gains the offices/rules columns. The 15-2 defers resolved here: the `^(attendance|leave)_` pg_proc privilege scan (MCP-side verification, hand-added map coverage), and the DTO-vocabulary/DB-CHECK cross-pin (MCP catalog query pinning the CHECK literals against the DTO constants).
- **e2e boundary spec** — 15-2 defer: `test/attendance.e2e-spec.ts` is added in this story (the module grows its first non-setup endpoints), pinning route mounting, `@Roles(Role.OWNER)` 403s and ValidationPipe 422s at the HTTP boundary.
- **api-contracts.md** — the Attendance setup section (added 15-2) sits between Reports and Sync; the Offices section slots directly after it; Endpoints tree at L40 gains the offices subtree.
- **Unit-test conventions** — `src/attendance/attendance.service.spec.ts`: mock-admin dispatch on first chained method, chain builders, `expectErrorCode` ⟨15-2⟩.

## Tasks & Acceptance

**Execution:**
- [ ] `supabase/migrations/20260926000005_attendance_offices_tables.sql` — `CREATE EXTENSION IF NOT EXISTS btree_gist;` + create:
  - `attendance_offices` (`id UUID PK DEFAULT gen_random_uuid()`, `tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE`, `name TEXT NOT NULL`, `latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90)`, `longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180)`, `radius_m INTEGER NOT NULL CHECK (radius_m BETWEEN 50 AND 1000)`, `archived_at TIMESTAMPTZ`, `created_at/updated_at`, `UNIQUE (tenant_id, lower(name))`).
  - `attendance_office_rules` (`id UUID PK DEFAULT gen_random_uuid()`, `office_id UUID NOT NULL REFERENCES attendance_offices(id) ON DELETE RESTRICT` (history never cascaded), `tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE`, `valid DATERANGE NOT NULL CHECK (NOT isempty(valid))`, `start_time TIME NOT NULL`, `end_time TIME NOT NULL CHECK (end_time > start_time)`, `late_cutoff_minutes INTEGER NOT NULL CHECK (late_cutoff_minutes BETWEEN 0 AND 120)`, `full_day_hours NUMERIC(4,2) NOT NULL CHECK (full_day_hours > 0)`, `half_day_hours NUMERIC(4,2) NOT NULL CHECK (half_day_hours > 0 AND half_day_hours < full_day_hours)`, `created_at/updated_at`, `EXCLUDE USING gist (office_id WITH =, valid WITH &&)`).
  - RLS enabled, no policies, `update_updated_at_column` triggers on both. Apply via MCP; verify schema + exclusion constraint live.
- [ ] `supabase/migrations/20260926000006_rpc_attendance_office_lifecycle.sql` — four functions, each with the AD-3 triple in-file:
  - `attendance_create_office(p_tenant_id, p_actor_id, p_name, p_latitude, p_longitude, p_radius_m, p_start_time, p_end_time, p_late_cutoff_minutes, p_full_day_hours, p_half_day_hours) RETURNS uuid` — insert office + rules `valid [attendance_today(tenant), ∞)`; returns the office id. Unique-name violation (`23505` on the index) → raise PT409 HINT `ATTENDANCE_OFFICE_NAME_TAKEN`.
  - `attendance_update_office_rules(p_tenant_id, p_actor_id, p_office_id, p_start_time, p_end_time, p_late_cutoff_minutes, p_full_day_hours, p_half_day_hours) RETURNS void` — exclusive tenant lock; office must exist, be in the tenant, not archived (else PT404 HINT `ATTENDANCE_OFFICE_NOT_FOUND`); AD-8 algorithm with `effective_from = attendance_today + 1`.
  - `attendance_archive_office(p_tenant_id, p_actor_id, p_office_id) RETURNS void` — exclusive tenant lock; blockers via the 15-7 tables (lazy-compiled; fail loud until 15-7); none → `archived_at = now()`; blockers → PT409 HINT `ATTENDANCE_OFFICE_ARCHIVE_BLOCKED`.
  - `attendance_office_archive_blockers(p_tenant_id, p_office_id) RETURNS TABLE(employee_id uuid, employee_name text)` — read/preview function (AD-24); queries the 15-7 tables (lazy-compiled); SECURITY DEFINER, service_role only.
  - No `attendance_complete_setup` recreation here: migration `20260926000003` already filters `o.archived_at IS NULL` in gate 1 (verified 2026-09-26); gate 2 stays deferred to 15-7 as planned.
  - Apply via MCP; verify ACLs (anon/authenticated denied, service_role granted) for all new + recreated functions.
- [ ] `src/common/enums/error-code.enum.ts` — add `ATTENDANCE_OFFICE_NOT_FOUND`, `ATTENDANCE_OFFICE_NAME_TAKEN`, `ATTENDANCE_OFFICE_ARCHIVE_BLOCKED` under `// Attendance (Epic 15)`.
- [ ] `src/attendance/offices.service.ts` + `offices.controller.ts` (`@Controller('attendance/offices')`, `@Roles(Role.OWNER)` on every route, Swagger blocks; registered in `attendance.module.ts`; split files if > ~300 lines):
  - `GET /api/v1/attendance/offices?includeArchived=` — list, tenant-scoped; each office carries `rule` (covering `attendance_today()`) and `nextRule` (earliest future range) or null.
  - `GET /api/v1/attendance/offices/:id` — detail incl. full rule history (effective-dated, ascending).
  - `POST /api/v1/attendance/offices` — `CreateOfficeDto` (name up to 80 chars — API-edge cap decided in the 2026-09-26 review; DB column has no length CHECK, latitude, longitude, radiusM default 100, startTime, endTime, lateCutoffMinutes default 15, fullDayHours default 8, halfDayHours default 4; class-validator ranges mirroring the DB CHECKs plus cross-field mirrors `endTime > startTime` and `halfDayHours < fullDayHours`) → RPC; 201.
  - `PATCH /api/v1/attendance/offices/:id` — `UpdateOfficeDto` (all optional: profile group + rules group); service routes profile → guarded UPDATE (tenant + `archived_at IS NULL` filter; zero rows → 404) and rules → RPC; at least one field required.
  - `POST /api/v1/attendance/offices/:id/archive` — RPC; maps PT409 + blockers (preview function output) → 409 `ATTENDANCE_OFFICE_ARCHIVE_BLOCKED` with `blockers` in the error extra.
  - `GET /api/v1/attendance/offices/:id/archive/preview` — blockers function read; 200 `{ officeId, blockers: [...] }`.
- [ ] `docs/api-contracts.md` — `### Attendance offices (Epic 15, Story 15-3, owner only)` section after the setup section; Endpoints tree updated.
- [ ] 15-2 defers resolved in this story: `test/attendance.e2e-spec.ts` (HTTP boundary: mounting, 403 technician, 422 validation); `^(attendance|leave)_` pg_proc privilege scan via MCP-side verification recorded in the spec's Verification section; DTO/CHECK cross-pin (MCP catalog query vs DTO constants, recorded in the integration spec or the verification log).
- [ ] Post-user-confirmation tests (per test-timing rule, only after the user confirms offices work): `offices.service.spec.ts` + `offices.controller.spec.ts` (mock-admin chain pattern per 15-2), catalog-pin extension in `rls-isolation.integration.spec.ts` (4 new RPCs → anon/authenticated `42501`; schema pins), real-DB probes (create → initial rule covering today; rules edit → tomorrow clipping + no overlap; duplicate name → PT409).

**Acceptance Criteria:**
- Given the migrations applied, when `pg_extension`/`information_schema` are inspected, then `btree_gist` is enabled, both tables exist with RLS enabled and no public policies, the exclusion constraint exists on `attendance_office_rules`, and every new (and recreated) function is SECURITY DEFINER with anon/authenticated denied and service_role granted.
- Given an owner creating an office with radius 100, 10:00–18:00, cutoff 15, 8/4 h, when the create RPC runs, then the row is saved with an initial rule `valid [today, ∞)`; duplicates (case-insensitive) are rejected with `ATTENDANCE_OFFICE_NAME_TAKEN`; out-of-range values are rejected by DTO (422) and DB CHECKs.
- Given an owner editing rules today, when the edit RPC runs, then the rule takes effect from tomorrow (covering range clipped at tomorrow, new range `[tomorrow, ∞)`), all past dates keep the rule active on that date, and a second same-day edit replaces the future range without overlap (exclusion constraint holds).
- Given an owner archiving an office with currently-tracked employees, when the archive RPC runs, then it is rejected with the blocker list (via `attendance_office_archive_blockers`); once no blockers remain, `archived_at` is set and the row is never deleted.
- Given all previously green suites run after the change, then every one stays green (additive change; no existing route or behaviour touched).

## Design Notes

**Why one PATCH route with an internal split:** the user's decision — profile (name/pin/radius) is not effective-dated, so it is a guarded single-row UPDATE (the AD-3 single-table exception); rules are effective-dated and multi-range, so they are the RPC. One FE contract, two write mechanics chosen by which field groups are present.

**Why rules edits are an RPC, profile edits are not:** the AD-8 algorithm touches multiple row-sets (delete future ranges, clip covering range, insert new) — exactly AD-3's RPC territory. Name/pin/radius is a single-row, single-table write with no side effects — the sanctioned plain-write exception, same as the 15-2 step marker.

**Why create needs no idempotency key:** AD-6 excludes the idempotency interceptor from attendance routes. Office create is FE-guarded (single submit); the DB unique-name index bounds the blast radius of a double-tap to a 409, not a duplicate row.

**Why the blocker list travels via the preview function, not the raise:** PL/pgSQL can only carry blockers through `RAISE` message text, which would force the service to parse strings. The service calls `attendance_office_archive_blockers` on PT409 and assembles the 409 body (`blockers` in `extra` through the GlobalExceptionFilter) — the same read function powers the GET preview route (AD-24's "previews share the validation path with the writes").

**Why `ON DELETE RESTRICT` from rules → office:** history is never cascaded away (consistency conventions); offices are archived, never deleted (AD-25), so the restrict never fires in practice but guards against accidental office deletion.

**Why `lower(name)` in the unique index:** owner-typed duplicates like "Thane Office"/"thane office" must not both exist; the DTO does no case-folding, the index is the single guard.

**Why the complete_setup gate-1 tweak was dropped:** on applying this story's migration, gate 1 in `20260926000003` turned out to already filter `o.archived_at IS NULL` — the anticipated one-line correction was never needed; the spec task is void and gate-2 runtime verification stays with 15-7 (enrolments), per the 15-2 plan.

## Verification

(to be filled during implementation — commands, MCP probes, walkthrough, post-confirmation tests)

### Applied 2026-09-26 (implementation, pre-tests)

**Migrations** (via Supabase MCP, project `pnlvreaijzslfymlnoti`):
- `20260926000005_attendance_offices_tables.sql` — `btree_gist` (1.7), both tables, unique index `(tenant_id, lower(name))`, exclusion constraint, RLS enabled/zero policies, `update_updated_at_column` triggers.
- `20260926000006_rpc_attendance_office_lifecycle.sql` — all four functions SECURITY DEFINER with `SET search_path = public`, `REVOKE EXECUTE FROM PUBLIC, anon, authenticated`, `GRANT EXECUTE TO service_role` (catalog-verified per function).

**PL/pgSQL functional probes** (temp `probe_15_3` table, all rolled back after):
- create → office + rule `valid [today, ∞)`; case-insensitive duplicate → `PT409` HINT `ATTENDANCE_OFFICE_NAME_TAKEN`.
- rules edit → covering range clipped at tomorrow + new `[tomorrow, ∞)`; a second same-day edit replaces the future range (exclusion constraint holds); unknown office → `PT404` HINT `ATTENDANCE_OFFICE_NOT_FOUND`.
- archive pre-15-7 → fails loud (`42P01`, undefined relation) — the lazy-compiled contract holds.
- rule CHECK violation → `23514`; probe rows cleaned (rules before office, `ON DELETE RESTRICT` respected).

**Post-confirmation tests (user confirmed via walkthrough acceptance, 2026-09-26):**
- `src/attendance/offices-response.model.spec.ts` (23) — pure model: range parsing, HH:mm/numeric mapping, ascending history, current/next picks (inclusive-from / exclusive-to edges).
- `src/attendance/offices.service.spec.ts` (31) — 15-2 mock-admin chain pattern: list mapping + scoping, create RPC args + PT409/23514/500 mapping, guarded-UPDATE profile path vs complete-set rules path, partial/empty PATCH 400s, rename 23505 → 409, archive 409 body assembled from the preview function, fail-loud 42P01s, no-tenant 400s.
- `src/attendance/offices.controller.spec.ts` (17) — delegation + route metadata (paths, methods, @HttpCode, owner-only on all six handlers).
- `test/attendance.e2e-spec.ts` (15) — HTTP boundary (15-2 defer resolved): mounting, guarded PATCH, 422s (unknown step / radius 40 / '25:00'), 403 technician on both route groups, 401 missing JWT, 201 create, 204 archive, 400/404 mappings.
- `rls-isolation.integration.spec.ts` — 4 new RPCs added to the anon+authenticated 42501 catalog pin; new "Attendance offices" real-DB probe: schema pins, anon/foreign-JWT empty reads vs service-role visibility, create → rule `[today, ∞)`, PT409 dup, PT404 unknown, tomorrow-clip edit (+ second same-day edit replaces the future range), GIST overlap → 23P01, CHECK → 23514, blockers/archive version-tolerant (42P01 pre-15-7 or clean archive + idempotent no-op post-15-7). Probe ids 092/093/094, cleaned in FK order.
- **Baseline e2e repairs (pre-existing, unrelated to 15-3):** `test/app.e2e-spec.ts` and `test/auth.integration.spec.ts` were still failing since the 2026-09-21 health-prefix commit (a60fb30) — their test apps had a stale/no `setGlobalPrefix`. Both now mirror `main.ts` (`exclude: ['internal/webhooks/storage']`), restored to green.

**Suite state:** unit `bun run test` 57 suites / 829 passed (was 54/758); e2e+integration `test:e2e` 17 suites / 297 passed (incl. the real-DB integration probes); `bunx tsc --noEmit` 65 errors = the unchanged baseline, 0 from `src/attendance` or the new test files.

**MCP-side verifications (pg_catalog is not exposed over PostgREST):**
- **pg_proc privilege scan** (`^(attendance|leave)_`, project `pnlvreaijzslfymlnoti`): all 9 `attendance_*` functions are `prosecdef = true` with grants only to `postgres` and `service_role` (OIDs 16388/16486); zero grants to PUBLIC/anon/authenticated.
- **DTO/CHECK cross-pin:** `radius_m BETWEEN 50 AND 1000`, `late_cutoff_minutes BETWEEN 0 AND 120`, `full_day_hours > 0`, `half_day_hours > 0 AND < full_day_hours`, `end_time > start_time`, `NOT isempty(valid)`, latitude/longitude bounds — every one mirrors the `create-office.dto.ts` constants/ranges (`OFFICE_RADIUS_MIN/MAX`, `OFFICE_LATE_CUTOFF_MIN/MAX`, `@Min(0.01)` hours, `TIME_PATTERN` HH:mm). The GIST exclusion index and the `UNIQUE (tenant_id, lower(name))` index are pinned as created.

**tsc:** `bunx tsc --noEmit` = 65 errors — exactly the 15-2 baseline; 0 from `src/attendance`.

**Unit suite:** 54 suites, 758/758 passed (15-2 baseline parity; no new tests yet).

**Live HTTP walkthrough** (owner + technician HS256 JWTs minted from `SUPABASE_JWT_SECRET`; Nest on :3000):
1. GET offices → `200 []`.
2. POST create "Andheri West" → `201` with seeded rule `validFrom 2026-09-26`.
3. GET list → `200` — rule `[2026-09-26, 2026-09-27)` + pending `nextRule [2026-09-27, ∞)`.
4. GET detail → `200` full history ascending.
5. PATCH profile (radius 150 → 200) → `200`; PATCH rules (full set) → `200` with clipped + new ranges.
6. POST duplicate name (case-insensitive "ANDHERI WEST") → `409 ATTENDANCE_OFFICE_NAME_TAKEN`.
7. PATCH partial rules set → `400 VALIDATION_ERROR` ("complete set" message); PATCH empty body → `400` "Nothing to update".
8. GET `/:id/archive/preview` → `500` fail loud pre-15-7 (undefined relation) — expected lazy-compiled behaviour.
9. POST `/:id/archive` → `500` fail loud pre-15-7 — expected.
10. Technician JWT GET → `403 FORBIDDEN`.

Probe office deleted (rules then office; `offices_left = 0`, `rules_left = 0`).

**Fixes found by the walkthrough** (folded into the implementation):
- supabase-js daterange `cs` filter unreliable → fetch-and-pick rule selection (see deviation above).
- `throwRpcError` initially missed the `ATTENDANCE_OFFICE_NAME_TAKEN` hint branch → duplicate POST mapped to 500 instead of 409; branch added and re-verified.
### Review Findings

**BMAD code review 2026-09-26** — 4 layers × 3 chunks (SQL/DTOs, service/controller/model, tests/docs). 12 subagent passes; triage below.

**Decision-needed**

- [x] [Review][Decision] Archive success status: shipped 204, frozen I/O matrix says 200 — docs + controller/e2e tests consistently pin 204; the matrix row was never renegotiated. Keep 204 (amend matrix) or change code to 200?
- [x] [Review][Decision] `@MaxLength(80)` on office `name` is undocumented — no spec basis, no DB CHECK (migration `20260926000005` leaves `name text` free). Keep the DTO cap and document it in spec + api-contracts, drop it, or also add a DB CHECK?
- [x] [Review][Decision] Cross-field rules (`endTime > startTime`, `halfDayHours < fullDayHours`) are enforced only by DB CHECKs — the I/O matrix pins pre-DB 422 via "class-validator mirrors". Add DTO cross-field validators (spec-literal) or accept DB-level rejection (patch makes it 422, but not pre-DB)?
- [x] [Review][Decision] `attendance_office_rules` lacks a composite FK `(office_id, tenant_id) → attendance_offices(id, tenant_id)` — a rule row can carry a different tenant id than its office on any non-RPC write path. Add hardening migration or defer to 15-7?

**Patch**

- [x] [Review][Patch] DB CHECK violations (23514) map to 400 but spec/docs/comments say 422; also `22003` (numeric(4,2) overflow, e.g. fullDayHours 150) is unmapped → 500, and DTOs lack the `@Max(99.99)` mirror [src/attendance/offices.service.ts:418]
- [x] [Review][Patch] `readRulesForOffices` has no `.eq('tenant_id')` while sibling `readAllRules` does — violates the explicit-tenant-filter constraint [src/attendance/offices.service.ts:314]
- [x] [Review][Patch] New e2e uses stale prefix exclude `['health']` — same value this diff repairs elsewhere; must be `internal/webhooks/storage` per main.ts [test/attendance.e2e-spec.ts:134]
- [x] [Review][Patch] Docs + model header claim the DB selects today's rule via daterange containment — implementation is the recorded fetch-and-pick deviation [docs/api-contracts.md, src/attendance/offices-response.model.ts:1]
- [x] [Review][Patch] Missing service-spec tests: mixed profile+rules PATCH body; `attendance_today` failure → 500; PT404 `ATTENDANCE_TENANT_NOT_FOUND` hint → 404 [src/attendance/offices.service.spec.ts]
- [x] [Review][Patch] Missing e2e tests: 409 name-taken at HTTP boundary; `?includeArchived=1` → 422; POST omitting optional fields → seeded defaults [test/attendance.e2e-spec.ts]
- [x] [Review][Patch] Missing real-DB probes: `end_time ≤ start_time` → 23514; `half ≥ full` → 23514; cross-tenant RPC call → PT404 [test/integration/rls-isolation.integration.spec.ts]
- [x] [Review][Patch] Probe-id reuse: attendance block reuses `…092` (users probe) and `…093` (jobs probe customer) — renumber to fresh ids and fix stale "unused by the other probes" comments [test/integration/rls-isolation.integration.spec.ts:1666]
- [x] [Review][Patch] e2e mock silently resolves unqueued table reads with null — throw on unexpected table [test/attendance.e2e-spec.ts:85]
- [x] [Review][Patch] createOffice: null RPC data falls into readOffice → misleading 404; guard with internal error [src/attendance/offices.service.ts:131]
- [x] [Review][Patch] Archive PT409: if the blockers read fails, the 500 masks the real 409 conflict — best-effort empty blockers [src/attendance/offices.service.ts:255]
- [x] [Review][Patch] Cosmetics: missing trailing newlines on 4 new files; duplicate import statement in model spec; controller-spec comment contradicts its own literals [4 test files, src/attendance/offices-response.model.spec.ts, src/attendance/offices.controller.spec.ts]

**Deferred**

- [x] [Review][Defer] No pagination/search on office list (unbounded for many archived offices) [src/attendance/dto/list-offices-query.dto.ts] — deferred, pre-existing concern; 15-4 UX story decides
- [x] [Review][Defer→Done 2026-09-26] No UUID validation on `:id` params — completed same day: controller `requireOfficeId` guard → 400 VALIDATION_ERROR (+ e2e pin) [src/attendance/offices.controller.ts]
- [x] [Review][Defer] Blockers RPC unbounded/unordered/possible duplicates + copy-pasted blocker predicate between archive and preview [supabase/migrations/20260926000006] — deferred, 15-7 owns these lazy-compiled functions
- [x] [Review][Defer] Version-tolerant 42P01 archive/blockers probes never auto-tighten after 15-7 [test/integration/rls-isolation.integration.spec.ts] — deferred, tracked in spec's 15-7 note
- [x] [Review][Defer→Done 2026-09-26] Office-name trimming/whitespace strategy — completed same day: `@Transform` trim on both DTOs (whitespace-only → 422; + e2e pin) [src/attendance/dto/create-office.dto.ts]

**Resolution (2026-09-26, same day):** all four decisions resolved to patches and applied — archive stays 204 (matrix row amended above); name cap ≤ 80 kept and documented (api-contracts + task list); DTO cross-field validators added (`office-rules.validators.ts`); composite FK shipped as migration `20260926000007` (UNIQUE (id, tenant_id) + rules (office_id, tenant_id) → offices, ON DELETE CASCADE) and applied via MCP. All 12 patch items fixed: 23514/22003 → 422 + `@Max(99.99)` mirrors, tenant filter on `readRulesForOffices`, e2e prefix + unexpected-table guard, docs corrected (fetch-and-pick, archived-office GET, 80-char note), new service-spec tests (mixed PATCH body, today-failure 500, tenant-hint 404, 22003, blockers-read-failure), new e2e tests (defaults POST, 409 name-taken, includeArchived=1 422), new real-DB probes (inverted times, half ≥ full, composite FK 23503, foreign-tenant RPC PT404), probe ids renumbered to 096-098, null-data guard, best-effort blockers on archive 409, cosmetics.

**Post-fix suite:** unit 57 suites / 834 passed; e2e + real-DB integration 17 suites / 300 passed; tsc 65 errors = unchanged baseline (0 from attendance files).

**Amendment 2 (2026-09-26, later same day — archive pre-15-7):** during the 15-4 device walkthrough the user's archive call returned 500: the `attendance_archive_office` blocker probe (referencing `attendance_office_assignments`, which no migration creates until 15-7) failed at **plan time** — Postgres 42P01, confirmed in production DB logs. The original "fail loud" decision blocked the 15-4 archive walkthrough, so it was amended: migration `20260926000008_archive_blocker_table_guard.sql` re-creates `attendance_archive_office` with the probe **nested in an IF branch** keyed on `to_regclass('public.attendance_office_assignments') is not null` (PL/pgSQL plans a statement only when first executed — the flag keeps the missing-table probe unreached pre-15-7; the probe **must not** be AND-ed into one condition, which still plans and still 42P01s). Pre-15-7 archive is therefore a clean 204 (nothing can be assigned yet); post-15-7 the check self-activates and 15-7 still owns the full predicate. The preview RPC stays fail loud (FE never calls it; 15-9 owns the shortcut). Applied via MCP, verified live in a rolled-back transaction (archive ran, 42P01 gone, office left unarchived); `rls-isolation` (c4) probe comment amended — the probe already accepted both branches.
