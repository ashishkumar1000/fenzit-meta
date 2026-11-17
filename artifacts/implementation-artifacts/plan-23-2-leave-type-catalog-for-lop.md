---
title: 'Epic 23 story 2 — Leave-type catalog for LOP (BE)'
type: 'feature'
ticket: '23-2'
created: '2026-11-17'
status: 'in-progress'
route: 'full'
route_source: 'auto'
baseline_revision: 'a195de7'
context:
  - 'artifacts/specs/spec-payroll/canonical-fixture.md'
  - 'artifacts/specs/spec-payroll/SPEC.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Leave has no paid/unpaid typing — `leave_requests.reason` is free text — so the run engine (story 6) cannot derive LOP from unpaid leaves (CAP-12).

**Approach:** Zero new RPCs. Migration adds a per-tenant `leave_types` catalog (name + paid flag) and a nullable `leave_requests.leave_type_id` link; NestJS-first config CRUD plus a typing endpoint for existing requests; employee apply accepts an optional `leaveTypeId`. NULL type reads as paid (safe default — no LOP surprise). The confirmed mapping (owner, 2026-11-17) is the create-time default: casual/sick/earned → paid, unpaid/LOP → unpaid, anything else → paid; explicit `paid` always wins.

## Boundaries & Constraints

**Always:** Zero new RPCs/DB functions — DDL migration + NestJS table writes only (AD-3). New table deny-by-default RLS, revoked from anon/authenticated, commented; the type link is a composite FK `(id, tenant_id)` so a cross-tenant link is impossible. Explicit `.eq('tenant_id', caller.tenantId)` everywhere. Uniqueness probe + `23505` → 409 naming the name (23-1 pattern; PATCH runs the same probe excluding itself); in-use delete → 409 plain English (probe + `23503` backstop); `paid`/`name` have no clear verb — null rejected 422. When create applies a keyword default, the response copy states the applied marking. Catalog changes and request typing audited via existing `write_audit_row` (`leave.type_created` / `leave.type_updated` / `leave.type_deleted` / `leave.request_typed`), details = changed-field names + old/new paid flag only. Reclassification semantics: rows are mutable config — a run (story 6) resolves typing at execution time; nothing snapshots here (locked months are story 7's concern). Plain-English copy says paid/unpaid leave.

**Never:** No auto-seed of per-tenant rows (no precedent; catalog starts empty per tenant). No run-engine or LOP derivation logic (story 6). No lock/snapshot machinery (story 7). No mobile/web UI. No change to the leave state machine, overlap index, or day-status engine. No new permission inside ADMIN_PERMISSIONS.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Create with default marking | POST "Casual Leave" (no `paid`) | 201; paid=true per confirmed mapping; audit row | — |
| Create unpaid default | POST "LOP" (no `paid`) | 201; paid=false; audit row | — |
| Explicit flag wins | POST "Special" paid=false | 201; paid=false | — |
| Duplicate name | same name again in tenant | rejected naming the name | 409 |
| Rename/flip | PATCH :id name+paid | 200; persisted; audit row | — |
| Rename into a duplicate | PATCH :id name → a name another type wears | rejected naming the name (excluded-self probe) | 409 |
| Clear a non-clearable | PATCH :id {paid: null} or {name: null} | rejected — paid has no clear verb | 422 |
| Rejected leave drops out | a typed leave's day rows → rejected | the approved-only join stops reading them (journey leg asserts) | — |
| Delete in use | DELETE type referenced by requests | rejected, says leaves use it | 409 |
| Delete unused | DELETE type with no references | 204 | — |
| Type a request | PATCH /attendance/leave/:id/type with typeId | 200; day-row join now reads the type; audit row | — |
| Clear a typing | same with null | 200; link NULL (= paid) | — |
| Unknown/foreign type id | typeId of other tenant or random uuid | rejected | 404 |
| Non-admin config call | employee/viewer token | forbidden | 403 |

</frozen-after-approval>

## Code Map

- `supabase/migrations/20260929000001_attendance_leave_tables.sql:36-93,107-109,150-172,184-196` -- leave_requests/leave_request_days schema, part on the REQUEST, day-row state machine, RLS+revoke idiom; `grid-reader.ts:282-292` is the day-row JOIN the run will mirror (approved rows + `r.part`).
- `src/attendance/offices.controller.ts` + `dto/create-office.dto.ts` -- the NestJS-first tenant-catalog CRUD idiom to copy (table writes, `@Can`, DTO style); holidays rides legacy RPCs — do NOT copy that.
- `src/common/permissions/permissions.ts` -- Permission union + ROLE_PERMISSIONS; new `leave.types` goes company_admin-only OUTSIDE ADMIN_PERMISSIONS, pinned in `src/common/permissions/job-role-grants.spec.ts` (23-1 patch pattern, lines 37-53).
- `src/members/members.service.ts:600-716` + `src/members/dto/update-employment.dto.ts` -- the 23-1 service idioms to reuse verbatim: tri-state null handling, probe+23505→409, field-by-field payload, try/catch'd `write_audit_row`, plain-English 422s; `employment-view.dto.ts` shows the swagger-class 200 idiom.
- `src/attendance/leave.controller.ts:45-160`, `leave.service.ts:68`, `leave.repository.ts` -- the leave module the config surface joins; apply DTO lives in `src/attendance/dto/` (add optional `leaveTypeId`).
- `test/payroll-journey.e2e-spec.ts` -- 13 legs + helpers (`must`, `employmentRowOf`, `ownerHeaders`, admin client seed idiom); extend with the typing legs; seed approved leave + day rows directly (all-NOT-NULL columns listed in Implementation Notes of the investigation).
- `src/customers/import/import-commit.service.ts:237-244` -- app-side audit idiom (already known).

## Tasks & Acceptance

**Execution:**
- [ ] `supabase/migrations/20261117110000_leave_type_catalog.sql` -- create `leave_types` (id, tenant_id FK, name varchar(60), paid boolean default true, timestamps, unique(tenant_id,name), RLS+revoke+comments); alter `leave_requests` add `leave_type_id` composite FK `on delete restrict` + comment (NULL = paid until typed). Apply via Supabase MCP; record row counts.
- [ ] `src/common/permissions/permissions.ts` + `job-role-grants.spec.ts` -- `leave.types` union entry, COMPANY_ADMIN-only outside ADMIN_PERMISSIONS, grant pins (all four roles + null).
- [ ] `src/attendance/dto/leave-type.dto.ts` -- Create/Update DTOs (name 1-60, optional paid) + SetLeaveRequestTypeDto (leaveTypeId string|null); plain-English messages.
- [ ] `src/attendance/leave-types.service.ts` + `leave-types.controller.ts` (`@Controller('attendance/leave/types')`) -- GET list / POST / PATCH :id / DELETE :id, `@Can('leave.types')`; name-keyword default marking per the confirmed mapping; uniqueness probe+23505→409; in-use delete probe+23503→409; audit each mutation.
- [ ] `src/attendance/leave.controller.ts` + `leave-types.service.ts` -- PATCH `attendance/leave/:requestId/type` (`@Can('leave.types')`): validate the request belongs to the tenant (404), validate the type belongs to the tenant (404), tri-state null-clear, audit `leave.request_typed`.
- [ ] Apply DTO (`src/attendance/dto/`) -- optional `leaveTypeId` on the employee apply + on-behalf path: validate tenant-owned type when present; NULL/absent keeps current behaviour.
- [ ] `src/attendance/leave-types.service.spec.ts` (+ controller spec REQUIRED-table pattern if the repo has one for this controller shape) -- unit tests: default marking table (casual/sick/earned/unpaid/lop/other), duplicate 409, in-use delete 409, cross-tenant 404s, tri-state typing, audit skip-on-noop.
- [ ] `test/payroll-journey.e2e-spec.ts` -- extend (~6 legs): create both fixture types via API → DB assert; duplicate 409; seed approved leave (Oct 13-15, full_day) + type it via API → SQL assert `leave_requests.leave_type_id` AND the day-row JOIN (grid-reader shape) reads paid=false; reclassify type paid→unpaid → join flips; delete-in-use 409; employee token 403 on config + apply-with-unknown-typeId 404.

**Acceptance Criteria:**
- Given the migration applied, then `leave_types` exists with deny-by-default RLS and `leave_requests.leave_type_id` is a composite FK; no existing leave row changed (all stay NULL = paid).
- Given the I/O matrix scenarios, each behaves as specified (201/200/204/403/404/409 as listed).
- Given an approved leave typed unpaid, then the exact JOIN the run will use (day rows ⋈ requests → type) returns paid=false for those dates, asserted at SQL level in the journey suite.
- Given the grant pins, then dropping `leave.types` from COMPANY_ADMIN fails a normal-path test.
- Given `bun run test`, `bun run typecheck`, and the journey e2e solo run, then all green except the stash-verified pre-existing reds.

## Implementation Notes

- (build agent, 2026-11-17) Migration `leave_type_catalog` applied via Supabase MCP, project `pnlvreaijzslfymlnoti`. **Pre-apply:** leave_requests **16** rows (32 day rows), 3 tenants with leave data (max 4 requests in one), `leave_types` did not exist, FK absent. **Post-apply:** leave_requests **16 (unchanged)**, day rows **32 (unchanged)**, `leave_type_id` non-null **0** (every request stays untyped = paid), `leave_types` **0 rows** (no seed, per plan), composite FK `leave_requests_type_tenant_fkey` present, RLS enabled on `leave_types`.
- (build agent, 2026-11-17) The composite FK needed a composite target: `leave_types_id_tenant_id_key unique (id, tenant_id)` (same idiom as `users_id_tenant_id_key` from 20260927000001). `on delete restrict` gives the in-use protection a storage backstop behind the API's probe-first 409 (`LEAVE_TYPE_IN_USE`).
- (build agent, 2026-11-17) `write_audit_row` details follow the plan literally: changed-field names + old/new **paid flag** only — type names are never copied into the audit log. For request typing the flags are the **effective** markings (NULL reads paid), so `old_paid`/`new_paid` always state what the run would act on before/after.
- (build agent, 2026-11-17) The typing route (`PATCH /attendance/leave/:requestId/type`) uses the leave row's own DB id — the same identifier every sibling owner route (`:id`) and the owner list hand back. `apply-without-type` unchanged behaviour is pinned by the pre-existing `leave.service.spec.ts` apply tests (they pass DTOs without the new field) plus the journey's refused-apply leg asserting nothing was written.
- (build agent, 2026-11-17) Journey suite now 20 legs (13 from 23-1 + 7 new): catalog create with both keyword defaults → DB assert; duplicate 409 (catalog size pinned at 2); seed approved leave Oct 13-15 + type via API → `leave_requests.leave_type_id` assert AND the grid-reader-shaped day-row JOIN (with `coalesce(t.paid, true)` — the run's NULL-reads-paid contract; the raw link asserted separately); reclassify paid→unpaid flips the JOIN; typed pending rows flipped pending→rejected (the legal transition — approved→rejected is guard-blocked) drop out of the approved-only JOIN; delete-in-use 409; employee 403 on the catalog + apply with unknown `leaveTypeId` → 404 with nothing written (counted by the apply's own idempotency request_id).
- (build agent, 2026-11-17) Unit tallies: `leave-types.service.spec.ts` 28 cases (keyword table, create defaults + appliedDefault only-when-defaulted, duplicate probe/23505 → 409 naming the name, null/blank → 422 no-clear-verb, excluded-self rename probe + self-name no-op skip, in-use delete probe/23503 → 409, tri-state typing incl. audit skip-on-noop, audit resolves-with-error + rejects, unknown-error 500 with no DB text); `job-role-grants.spec.ts` gains the leave.types pins (4 roles + null); `leave.repository.spec.ts` updated to the 9-parameter insert (9th = typing link, null default — the repository also normalises undefined → null). Full suite: **166 suites — 164 pass, 2 fail (sync, users — the stash-verified pre-existing reds, 6 tests); 2895 tests — 2889 pass, 6 fail.** `bun run typecheck` clean; journey solo run 20/20.
- (build agent, 2026-11-17) Code-review patches (12) applied and re-verified: in-use probe now `.limit(1)` (multi-row-safe) + the journey delete leg seeds a second referencing request; apply-path typed persistence pinned at unit level (leave_types branch in the fake SQL router; known type → insert's 9th param carries the id; unknown type → 404 RESOURCE_NOT_FOUND with no write); setRequestType 23503 → new `LEAVE_TYPE_CHANGED` 409 ("no longer available — reload and try again"); insert 23503 → `leaveTypeNotFound()`; update stamps `updated_at` itself (migration comment notes the app maintains it — no trigger by design) and `updatedAt` now rides the view/columns; update PGRST116 → 404; delete is row-returning — zero rows → 404 with NO audit entry (no phantom audit); `defaultPaidMarking` word-scopes 'unpaid' exactly like 'lop' with compound-word pins; `leaveTypeExistsInTenant` repositioned below insertLeaveRequest (docblock restored); swagger aligned (GET 400 dropped, POST 422 added, typing route 409 added); rejected-rows journey leg comment now states the flip is seed-level SQL with the request row staying pending. New unit pins: create `paid: null` → keyword default + appliedDefault; list ordering/empty/error; setRequestType 23503/PGRST116 branches; delete-removed-zero-rows → 404 no-audit. Re-verify: **166 suites — 164 pass, 2 fail (sync, users — the stash-verified pre-existing reds, 6 tests); 2906 tests — 2900 pass, 6 fail; typecheck clean; journey solo 20/20; lint clean on all files created this story** (leave.repository.spec.ts / leave.dto.ts / leave.service.spec.ts carry only HEAD-era lint idioms, verified against HEAD).

## Plan Change Log

## Review Triage Log

## Design Notes

- **Link on `leave_requests`, not day rows**: the run's LOP read joins day rows to their request anyway (grid-reader precedent), and `part` already lives on the request — one typing per span, no per-day duplication.
- **NULL = paid**: safe default direction — an untyped leave never causes an LOP deduction; the admin types historical rows via the new endpoint (web story 10 renders it).
- **No seed**: catalog starts empty per tenant; the four common types are one API call each from web story 10. Keyword defaulting carries the confirmed mapping so the default form answer is already right.
- **Why not reuse `attendance.manage`**: payroll config follows the 23-1 precedent (company-admin-only, outside ADMIN_PERMISSIONS) so platform admins don't hold tenant payroll configuration.

## Verification

**Commands:**
- `bun run test` -- expected: all unit suites green except the two stash-verified pre-existing reds.
- `node --env-file=.env node_modules/.bin/jest --config ./test/jest-e2e.json test/payroll-journey.e2e-spec.ts` -- expected: all legs pass (real DB).
- `bun run typecheck` -- expected: clean.

## Code Review

### 2026-11-17 (thorough: blind-hunter, edge-case-hunter, verification-gap, intent-alignment)

**Code review complete.** 0 `decision-needed`, 12 `patch`, 3 `defer`, 17 `rejected`.

- [x] [Review][Patch] Delete in-use probe breaks on ≥2 references: maybeSingle → PGRST116 → 500 on the ordinary used-type case [src/attendance/leave-types.service.ts:223-235] — make the probe multi-row-safe (.limit(1)), extend the journey leg with a second referencing request, assert 409.
- [x] [Review][Patch] Apply-path typed persistence never proven — a silently-NULL link ships green [src/attendance/leave.service.ts:216-230, leave.repository.ts] — unit case: dto with valid leaveTypeId + leave_types branch in the fake router; assert the request insert's 9th param carries the id.
- [x] [Review][Patch] setRequestType 23503 answers a delete-flavored message [src/attendance/leave-types.service.ts:328-336] — typing race (type deleted mid-flight) gets "used by existing leave requests and cannot be deleted"; fix to a typing-flavored conflict ("no longer available — reload").
- [x] [Review][Patch] Apply insert 23503 unmapped [src/attendance/leave.repository.ts:66-87] — type deleted between the tenant-ownership check and the insert surfaces a raw DB error; map 23503 → leaveTypeNotFound.
- [x] [Review][Patch] leave_types.updated_at never advances [migration + src/attendance/leave-types.service.ts] — no trigger (zero-functions boundary forbids one); the service update payload must set updated_at itself.
- [x] [Review][Patch] update PGRST116 → opaque 500 when the row vanishes mid-edit [src/attendance/leave-types.service.ts:176-192] — map to 404, consistent with the 23-1 pattern.
- [x] [Review][Patch] DELETE race can answer 204 + write leave.type_deleted audit for a deletion that never happened [src/attendance/leave-types.service.ts:237-255] — check the deleted-row count; 0 rows → 404, no audit.
- [x] [Review][Patch] Keyword discipline asymmetry: 'unpaid' substring vs word-scoped 'lop' [src/attendance/leave-types.service.ts:54-63] — unify both word-scoped; pin with tests (e.g. a compound containing 'unpaid' inside a word does not default unpaid).
- [x] [Review][Patch] Missing unit pins: create with paid:null (documented default path), list() ordering/empty/error, setRequestType 23503→409 and PGRST116→404 branches [src/attendance/leave-types.service.spec.ts].
- [x] [Review][Patch] Orphaned docblock: leaveTypeExistsInTenant inserted between insertLeaveRequest and its documentation [src/attendance/leave.repository.ts:34-55] — reposition the helper below the insert.
- [x] [Review][Patch] Swagger gaps: GET documents an impossible 400; POST create omits 422; PATCH :requestId/type omits its real 409 [src/attendance/leave-types.controller.ts, src/attendance/leave.controller.ts] — align annotations.
- [x] [Review][Patch] Journey leg comment overstates the rejection path [test/payroll-journey.e2e-spec.ts rejected-rows leg] — the state flip is seed-level SQL, not the owner API; reword the comment to say so.
- [x] [Review][Defer] FK index on leave_requests(leave_type_id, tenant_id) for the delete probe + RESTRICT checks — deferred: belongs to the OPEN pre-launch FK-index migration batch (46 indexes proposed, owner unanswered).
- [x] [Review][Defer] Case-insensitive catalog uniqueness (lower(name) unique) + DB-level whitespace check — deferred: needs a new migration; record for the pre-launch batch alongside the FK indexes.
- [x] [Review][Defer] Read-side exposure of a request's typing on the owner leave list/detail — deferred: web stories 10-11 own that surface; a no-op PATCH :id/type already returns the current effective marking as a stopgap.

**Rejected appendix:**
- Unicode case variants escaping the ASCII case-fold [edge-case-hunter] — false-in-practice: unreachable names; explicit flag always wins.
- Concurrent PATCH lost update / stale marking in setRequestType answer [edge-case-hunter] — rejected low: config rows are last-write-wins by design; no invariant violated (unlike 23-1 where a CHECK backstop existed).
- list() unbounded growth [edge-case-hunter + blind-hunter] — rejected low: admin-curated catalog; a 500-type company is not a real state.
- setRequestType ignores request state (cancelled/revoked typable) [edge-case-hunter] — planned semantics: the run joins approved-only, so typing dead requests is inert; the plan froze no state coupling.
- Audit changed_fields on create/delete are decorative [blind-hunter] — false: by design the audit carries field NAMES + paid flags only, never values ("never the type names" is the frozen privacy rule).
- Redundant leave_types_tenant_name_idx [blind-hunter] — rejected low: harmless on a tiny config table; removing it now means editing an applied migration (DB/file drift).
- Journey happy-path coverage gaps (list/DELETE-204/rename/clear at e2e level) [blind-hunter] — covered at unit level except the apply leg, which is patched above.
- Journey legs order-dependent via shared mutable state [blind-hunter] — house idiom (23-1 suite identical); single sequential runner.
- leaveTypeExistsInTenant serial before Promise.all + error precedence [blind-hunter] — rejected low: one extra indexed point query in a tx is noise; either error order is defensible.
- Unicode/compound-word keyword edge cases beyond word-scoping [edge-case-hunter] — covered by the word-scoping patch; further narrowing invents validation.
- Run-engine consumption enforced only against the test's own SQL mirror [intent-alignment] — scope: story 6 owns the production reader; the JOIN shape was the plan's stated test anchor and will re-anchor there.
- Keyword mapping encodes only the unpaid leg [intent-alignment] — extensionally identical to the confirmed mapping; the paid keywords are subsumed by the catch-all default.
- Typing endpoint under leave.types not leave.approve [intent-alignment] — planned: payroll config follows the 23-1 surface precedent.
- Dead 'unique (tenant_id, request_id)'.slice(0,0) test expression [blind-hunter] — pre-existing test oddity, untouched by this change.
