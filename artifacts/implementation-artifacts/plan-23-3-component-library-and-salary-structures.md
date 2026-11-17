---
title: 'Epic 23 story 3 — Component library and salary structures (BE)'
type: 'feature'
ticket: '23-3'
created: '2026-11-17'
status: 'in-progress'
route: 'full'
route_source: 'auto'
baseline_revision: '4802a29'
context:
  - 'artifacts/specs/spec-payroll/canonical-fixture.md'
  - 'artifacts/specs/spec-payroll/SPEC.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Pay has no vocabulary — no per-company salary components and no per-employee salary structures — so the run engine (story 6) has nothing to resolve a month's pay from (CAP-1, CAP-2).

**Approach:** Zero new RPCs. Migration adds two per-tenant config tables: `salary_components` (name + the one `is_basic` designation + `active`) and `salary_structures` (effective-dated rows per membership, lines as validated JSONB: amount or formula AST). NestJS config CRUD behind a new `payroll.config` permission (company_admin-only, outside ADMIN_PERMISSIONS — the 23-1/23-2 precedent). A pure formula module validates and evaluates the AST at save (cycle → 422 naming the chain; operand-without-amount; division by a zero-amount operand; negative result — all 422 plain English), and a pure effective-dating resolver picks the row for a run month (month-start: latest `effective_from ≤ first day of the run month`), the helper stories 4–6 reuse. Structures carry unique `(membership_id, effective_from)`; a same-date save REPLACES that dated row (upsert, single statement — the date bucket is the atomic unit of effective dating, locked months keep run-time snapshots so history is never corrupted).

## Boundaries & Constraints

**Always:** Deny-by-default RLS (enabled, no policies, revoke all from public/anon/authenticated, grant service_role) + comments on both tables. Composite FKs: structures `(membership_id, tenant_id) → memberships(id, tenant_id)` — the migration adds `memberships_id_tenant_id_key unique (id, tenant_id)` (same idiom as `leave_types_id_tenant_id_key`). Explicit `.eq('tenant_id', …)` on every read/write. Exactly one basic per tenant enforced in the service (create/PATCH conflict 409 naming the current basic; first component may carry `isBasic: true`). Rename always allowed (component names are display data; structures reference ids). Deactivate (`active: false`) refused while ANY structure row of the tenant references the component → 409 `SALARY_COMPONENT_IN_USE` listing referencing employees (truncated at 5 names + count). Reactivate allowed. Component used-by probe is multi-row-safe (`.limit(1)` for the existence check; the list query reads names separately). Duplicate component name → 409 `DUPLICATE_RESOURCE` (probe + 23505 backstop, PATCH probe excludes self). Row-returning writes; PGRST116 → 404; zero-rows delete/updates → 404 with no audit. `updated_at` stamped by the service on every real change (no trigger — zero-functions boundary). Every mutation audited via existing `write_audit_row` (`payroll.component_created` / `payroll.component_updated` / `payroll.structure_saved`), try/catch'd — audit failure never undoes the save. Formula AST limits: depth ≤ 8, nodes ≤ 32, finite numbers only. Money amounts in JSONB carried as strings (`"20000.00"`) — exact decimal text, never float. Same-tenant membership existence probe before a structure save (404 plain English). Amount lines must be ≥ 0; a line is amount XOR formula. Formula validation evaluates against the save payload's own amounts.

**Never:** No run-engine, LOP, or money-earning computation (story 6). No lock/snapshot machinery (story 7). No payslip machinery (story 8). No off-cycle lines (story 9). No web/mobile UI. No new DB functions/triggers (zero-RPC rule — service stamps `updated_at`). No DELETE endpoint on components (deactivate only — catalog rows are referenced config). No per-tenant seed rows. No component delete. No formula string mini-language on the wire — the AST JSON is the contract (unambiguous, cycle-checkable, directly evaluable); web story 10 renders the builder. No rounding beyond display (the run owns final rounding). No basic-component formula restriction beyond the structure-must-include-basic rule (a formula basic is legal config).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Create component | POST {name, isBasic?} | 201; view with id/name/isBasic/active/createdAt/updatedAt | — |
| Create duplicate name | name already in tenant | rejected naming the name | 409 DUPLICATE_RESOURCE |
| Flag basic when one exists | PATCH :id {isBasic: true}, another is basic | rejected naming the current basic | 409 BASIC_COMPONENT_EXISTS |
| Clear basic | PATCH :id {isBasic: false} | 200 (library may briefly have none) | — |
| Rename | PATCH :id {name} | 200; reflected from the next run (read-time resolution) | — |
| Rename into duplicate | PATCH to a name another wears | rejected naming it (excludes self) | 409 |
| Deactivate referenced | PATCH :id {active: false}, any structure references it | rejected listing referencing employees | 409 SALARY_COMPONENT_IN_USE |
| Deactivate unreferenced | no structure references it | 200; active=false | — |
| Reactivate | {active: true} | 200 | — |
| Save structure | PUT /members/:userId/salary-structures {effectiveFrom, lines} | 200; row stored; computed amounts in the response | — |
| Same-date save | same effectiveFrom again | replaces that dated row (one row for the date) | — |
| New date revision | different effectiveFrom | new row; both coexist | — |
| Structure without basic | lines omit the basic component | rejected plain English | 422 |
| Duplicate component line | same componentId twice | rejected | 422 |
| Unknown/foreign component in a line | componentId not in tenant library | rejected plain English | 422 |
| Negative amount line | {amount: "-5"} | rejected | 422 |
| Operand outside the structure | formula references a component not among the payload lines | rejected plain English ("no amount in this structure") | 422 |
| Formula cycle A→B→A | two formula lines referring to each other | rejected NAMING the chain (e.g. "A → B → A") | 422 |
| Division by zero operand | divisor evaluates to 0 with the payload's amounts | rejected plain English | 422 |
| Formula evaluates negative | computed amount < 0 | rejected plain English | 422 |
| Real-date check | effectiveFrom "2026-02-30" | rejected (real calendar parse) | 422 |
| Unknown member | :userId not a membership of the tenant | rejected, nothing revealed | 404 |
| Non-admin caller | employee/viewer/platform-admin token | forbidden | 403 |
| List structures | GET (revisions, oldest→newest) | dated rows with component names resolved at read time | — |

</frozen-after-approval>

## Elicitation (recorded, 4 methods)

- **Expand/contract:** expanded once — a GET on structures was added (web story 10 needs the revision list for its editor); contracted once — no component DELETE and no formula-string parser (AST only).
- **Risk screen:** (1) JSONB lines could drift shape → mitigated by save-time full validation + depth/node caps; (2) same-date upsert could mask an intended new revision → mitigated by unique (membership_id, effective_from) + audit entry carrying effectiveFrom; (3) basic-switch two-step could frustrate → accepted: predictable beats magic; the error names the current basic.
- **Red-team:** an admin could deactivate a component between structure-save probe and use → harmless: the run resolves and snapshots at run time (story 6); a deactivated component has zero referencing structures by the guard's construction.
- **Alternative scan:** relational `salary_structure_lines` child table rejected — the story mandates two config tables and the run snapshots whole rows; component-name-referencing formulas rejected — renames would rewrite history; string formula grammar rejected — parser ambiguity vs a typed AST.

## Code Map

- `supabase/migrations/20261117110000_leave_type_catalog.sql` — the RLS+revoke+comment idiom and the composite-FK (`unique (id, tenant_id)` target) idiom to copy verbatim.
- `src/attendance/leave-types.service.ts` / `.controller.ts` / `dto/leave-type.dto.ts` — the config-CRUD house style this story mirrors (probe+23505→409, row-returning writes, PGRST116→404, try/catch'd `write_audit_row`, service-stamped `updated_at`, `@Can` + swagger annotations).
- `src/members/members.service.ts` (`readEmploymentRow`, ~:465-516) — the membership-existence probe and the user-keyed member surface (`/members/:userId/employment`) that `/members/:userId/salary-structures` joins.
- `src/common/permissions/permissions.ts` — Permission union + ROLE_PERMISSIONS; new `payroll.config` goes COMPANY_ADMIN-only OUTSIDE ADMIN_PERMISSIONS; pins land in `src/common/permissions/job-role-grants.spec.ts`.
- `src/common/enums/error-code.enum.ts` — add `SALARY_COMPONENT_IN_USE`, `BASIC_COMPONENT_EXISTS`.
- `test/payroll-journey.e2e-spec.ts` — the journey suite this story extends (helpers: `must`, `ownerHeaders`, admin-client seed idiom; fixture state: Oct 6-7 + Oct 13-15 leaves approved-unpaid already seeded).
- `src/common/day-status/keys.ts` — untouched; listed only to mark the boundary (payroll never recomputes attendance).

## Tasks & Acceptance

**Execution:**
- [ ] `supabase/migrations/20261117120000_salary_components_and_structures.sql` — `salary_components` (id, tenant_id FK cascade, name varchar(60), is_basic boolean default false, active boolean default true, timestamps, unique(tenant_id, name)); `salary_structures` (id, tenant_id FK cascade, membership_id, effective_from date, lines jsonb not null, timestamps, unique(membership_id, effective_from), FK (membership_id, tenant_id) → memberships(id, tenant_id)); `memberships_id_tenant_id_key unique (id, tenant_id)`; RLS+revoke+grant+comments on both new tables. Apply via Supabase MCP; record row counts (pre/post: components 0, structures 0, memberships untouched).
- [ ] `src/common/permissions/permissions.ts` + `job-role-grants.spec.ts` — `payroll.config` union entry, COMPANY_ADMIN-only outside ADMIN_PERMISSIONS, grant pins (all roles + null).
- [ ] `src/common/enums/error-code.enum.ts` — `SALARY_COMPONENT_IN_USE` (409), `BASIC_COMPONENT_EXISTS` (409).
- [ ] `src/payroll/formula.ts` — pure AST types + validator/evaluator: shape check (depth ≤ 8, nodes ≤ 32, finite), reference resolution, cycle detection returning the chain (component names), zero-operand division, negative-evaluation, per-component unrounded values; half-up 2dp display rounding helper.
- [ ] `src/payroll/effective-dating.ts` — pure `resolveEffective<T extends {effectiveFrom: string}>(rows, month: 'YYYY-MM')`: latest row with `effective_from ≤ 'YYYY-MM-01'`, undefined when none.
- [ ] `src/payroll/dto/payroll-components.dto.ts` + `src/payroll/dto/salary-structures.dto.ts` — Create/Update component DTOs; structure PUT DTO with recursive formula validation (`class-validator` + custom validator walking the AST), plain-English messages.
- [ ] `src/payroll/payroll-components.service.ts` + `.controller.ts` (`@Controller('payroll/components')`, `@Can('payroll.config')`) — GET/POST/PATCH :id per the matrix.
- [ ] `src/payroll/salary-structures.service.ts` + `.controller.ts` (`@Controller('members/:userId/salary-structures')`, `@Can('payroll.config')`) — GET list + PUT save per the matrix (validation pipeline: membership 404 → real date → component ownership → shape → basic-included → per-line XOR → formula evaluate/cycle → upsert onConflict `(membership_id, effective_from)`; response carries display-rounded computed amounts).
- [ ] `src/payroll/payroll.module.ts` registered in `app.module.ts`.
- [ ] `src/payroll/*.spec.ts` — QA-mindset unit suites: formula table (cycle naming, zero-div, negative, limits, malformed), effective-dating table (empty, boundary, future-only, unordered input), components service (basic conflict, duplicate 409, in-use 409 with 5-name truncation, reactivate, audit noop-skip), structures service (full 422 matrix, upsert same-date vs new-date, 23505 backstop, PGRST116→404, cross-tenant probe).
- [ ] `test/payroll-journey.e2e-spec.ts` — extend (~8 legs): fixture components via API → DB assert; variant A structure (basic 20000 + HRA 40% → response computed 8000.00) + DB line assert + same-date replace; structure-without-basic 422; cycle 422 naming the chain (and re-checked on edit); zero-operand-division + negative-result 422s; variant F revision 2026-11-01 coexisting (GET shows both rows; resolver pinned at unit level); rename reflected in GET + deactivate-referenced 409 listing Employee A, deactivate-unreferenced 200; cross-tenant 404 + employee 403 + platform-admin-free surface.

**Acceptance Criteria:**
- Given the migration applied, then both tables exist with deny-by-default RLS, composite FKs, and no seed rows; memberships gains only the `(id, tenant_id)` unique.
- Given the I/O matrix, each scenario behaves as specified (201/200/403/404/409/422 as listed).
- Given variant A's payload, then the saved structure resolves to gross 28,000.00 (basic 20,000 + HRA computed 8,000.00) — the number variant F and story 6 build on.
- Given variant F's payloads, then the 2026-09-01 row and the 2026-11-01 row coexist and `resolveEffective` picks September's row for 2026-10 and November's row for 2026-11.
- Given the grant pins, then dropping `payroll.config` from COMPANY_ADMIN fails a normal-path test.
- Given `bun run test`, `bun run typecheck`, and the journey solo run, then all green except the stash-verified pre-existing reds (sync, users suites).


- (build agent, 2026-11-17) Review patches applied and re-verified: formula.ts (epsilon-scaled half-up rounding + non-finite guard), components service (23505 basic-index branch, contains+count bounded probe with JSON-stringified filter — supabase-js renders JS arrays as list syntax, found live: probe 400'd until stringified — tenant filter on the names read, reworded rename comment, documented probe-write race), structures service (updated_at on the upsert payload, 23505→422/PGRST116→404 mappings, 12-digit amount cap, amount normalisation in the no-op compare), dto (@Matches dropped — the calendar-date constraint validates shape and message). Migration 20261117140000_salary_basic_index_and_hygiene applied via MCP (partial unique basic index; drops the tautological check and the duplicate index; note: the runner recorded it under run-time version 20261117171255, file slot 20261117140000 kept in the filename).
- (build agent, 2026-11-17) Final tallies: payroll unit suites 4 / **122 tests green** (was 108; +14 review pins); journey e2e **31 legs green on the real DB** (same count, two legs deepened: the cycle leg now also proves the changed same-date REPLACE + updated_at stamp + audit count 3, the final leg adds platform-admin 403s, the renames leg closes with the owner-side library GET asserting order + flags); `bun run test` at the baseline (2 failed suites, 6 tests — sync/users pre-existing reds only); `bun run typecheck` clean; eslint clean on every file created or touched this story.

## Design Notes

- **AST on the wire, ids inside:** formulas reference component UUIDs, never names — renames can't rewrite pay history, and the AST validates/evaluates deterministically. Web story 10 renders names around it.
- **Same-date save replaces:** the dated row IS the configuration for every run month from that date until superseded; replacing it is an idempotent re-save, not history erasure — history lives in run snapshots (story 6+). Audit names `effectiveFrom` so the trail stays legible.
- **Exactly-one-basic in the service:** a DB partial unique index (`where is_basic`) would be storage backstop, but the zero-RPC/zero-trigger boundary plus a tiny table makes the service probe the honest owner; the 409 names the current basic.
- **Why `payroll.config` as one permission:** components, structures, and the calendar/heads stories 4–5 are one admin surface in one role's hands; splitting now buys nothing (ROLE_PERMISSIONS is the single place to split later).
- **Structures ride `/members/:userId/...`:** employment data set that precedent (story 1); the run resolves structure-by-membership internally, the admin surface is person-shaped.

## Verification

**Commands:**
- `bun run test` — expected: all unit suites green except the two stash-verified pre-existing reds (sync, users).
- `node --env-file=.env node_modules/.bin/jest --config ./test/jest-e2e.json test/payroll-journey.e2e-spec.ts` — expected: all legs pass (real DB).
- `bun run typecheck` — expected: clean.


## Code Review

### 2026-11-17 (BMAD thorough: edge-case-hunter, verification-gap, ponytail-review, intent-alignment)

**Code review complete.** 0 `decision-needed`, 9 `patch` (grouped), 2 `defer`, 8 rejected.
Subagent concurrency limited two lenses to in-session runs (the owner's other session held the slots); all four lens protocols executed and their findings triaged below. Intent-alignment subagent verdict: DIVERGENT→6 mechanical findings; verification-gap subagent verdict: ALIGNED (7 findings); ponytail verdict: "fix 1 and 2 first"; edge-case-hunter: 14 path findings.

- [x] [Review][Patch] Half-up rounding misses true .xx5 boundaries (`src/payroll/formula.ts` roundMoney) — 1.005→1.00, 150.075→150.07 while all tests stayed green; the 2.675 test comment was factually wrong. Fixed with the magnitude-scaled epsilon term, boundary fixtures added (1.005→'1.01', 150.075→'150.08'), comment corrected. (ponytail#1 + verification-gap#1)
- [x] [Review][Patch] Same-date structure replace never stamped `updated_at` (upsert payload omitted it; no trigger exists) — the GET answer reported stale freshness. Fixed: payload stamps it; unit pin + journey changed-same-date leg asserts updated_at ≠ created_at and exactly one row. (ponytail#2 + intent#1 + verification-gap#1/#3)
- [x] [Review][Patch] Exactly-one-basic had no storage backstop; two concurrent isBasic creates both landed AND bricked readBasicRow (maybeSingle ×2 rows → 500 on every later write). Fixed: partial unique index `salary_components_tenant_basic_uq` (migration 20261117140000, DDL not a function — zero-functions boundary holds) + 23505 branch mapping to BASIC_COMPONENT_EXISTS with the current basic's name; unit pins both branches + branch discipline (name-index violation still answers DUPLICATE_RESOURCE). (edge#4/#11 + ponytail#3)
- [x] [Review][Patch] Non-finite formula results accepted at save (const 1e308 × 1e308 → Infinity passes `value < 0`; NaN too). Fixed: `!Number.isFinite` rejection with plain-English message + overflow unit pins. (edge#1 + ponytail#4)
- [x] [Review][Patch] Deactivation probe loaded every structure row (Supabase max-rows could silently truncate at scale) and the names read lacked its explicit tenant filter. Fixed: server-side JSONB containment filter (`contains('lines', JSON.stringify([{componentId}]))` — supabase-js renders JS arrays as list syntax, so the JSON text is passed verbatim; verified 400→200 on the live REST) + exact-count head probe + range(0,4) display read + `.eq('tenant_id')` on the names read; truncation message pinned ('E1..E5 and 2 more'). (edge#8 + intent#3/#5a)
- [x] [Review][Patch] 14-digit amounts lose paise through Number() (>2^53/100). Fixed: AMOUNT_SHAPE capped at 12 integer digits (₹999.9B/month ceiling — beyond any payroll), message updated, unit pin. (edge#2/#12)
- [x] [Review][Patch] Structures upsert mapped every error to 500 — plan Always demands PGRST116→404 and a 23505 backstop. Fixed: 23505→422 naming the raced date, PGRST116→404; unit pins both. (intent#2)
- [x] [Review][Patch] Identical-resave no-op treated leading-zero amounts ("020000.00") as a change → spurious replace + audit. Fixed: amounts normalised through moneyText in the compare; leading-zero no-op pinned. (edge#9)
- [x] [Review][Patch] Coverage gaps the lenses proved: rename-into-taken-name never verified (unit pin added), >100-lines cap untested (pin), platform-admin 403 leg absent (journey leg added with a seeded platform_admin user), owner-side GET /payroll/components had no runtime coverage (journey asserts order + flags), changed same-date replace never exercised at DB level (journey leg added). Comment accuracy: "rename always allowed" reworded (taken name = 409); deactivation probe-write race documented as accepted-and-self-healing. (verification-gap#2/#4/#7, intent#4, edge#14, ponytail#8)
- [x] [Review][Defer] Case-insensitive component-name uniqueness (unique on lower(name)) — needs a new migration; recorded for the pre-launch batch alongside the identical 23-2 defer for leave_types. (edge#6)
- [x] [Review][Defer] effective-dating.ts ships with no production caller until stories 23-4/23-6 consume it (151 lines kept green for nothing yet) — plan-mandated file (frozen Tasks list it); recorded in deferred-work.md as consumed-by-later-stories rather than deleted. (ponytail#5 + verification-gap note)

**Rejected appendix:**
- Years 0001–0099 rejected by the Date.UTC round-trip validator [edge#3/#13] — real behaviour, unreachable input for payroll effective dating (modern dates), and the identical house idiom ships in 23-1's employment DTOs and attendance; a numeric leap-table validator adds complexity for nothing.
- Deactivation probe-write race [edge#5 + ponytail#8's fix option] — the re-probe-and-revert fix adds a second write path for a one-admin config-time race that self-heals on the next attempt; documented in the service instead (folded into the comment patch above).
- Structure saves allowed for invited/removed members [edge#7] — intended: preconfiguring salary before an invite lands is legitimate; the run population is active-membership-only, so such config is inert.
- Unbounded dated revisions per membership [edge#10] — a few rows per employee per year at any real usage; a cap invents semantics the plan never asked for (ponytail YAGNI concurs).
- payroll.helpers duplicate of the attendance helper pair [ponytail#7] — the finding itself recommends leaving it; the module seam is deliberate and commented; hoist if a third copy appears.
- Migration dead weight [ponytail#6 + intent#6] — PATCHED via migration 20261117140000 (drop tautological check + duplicate index), so not deferred/rejected — recorded here because two lenses flagged it.
- DTO letter deviation: deep formula validation lives in the service, not class-validator on the DTO [intent#6-info + verification-gap#6-info] — frozen Intent names the pure formula module as the validator; matrix outcomes identical; no action.
-effective-dating unit list test vacuity (fake ignores select/order) [verification-gap#4's structures-side note] — superseded by the owner-side journey GET leg which asserts real ordering + flags end to end.

**Review-verified DB state (Supabase MCP):** both salary tables RLS-on/no-policies, `salary_components_tenant_basic_uq` live, tautological check + duplicate index dropped, both migrations recorded in schema_migrations (20261117151108, 20261117171255 — the runner stamps run-time versions over the file-name slots).

## Plan Change Log

## Review Triage Log

## Implementation Notes

- (autonomous run, 2026-11-17) Migration `salary_components_and_structures` applied via Supabase MCP, project `pnlvreaijzslfymlnoti`. Pre-apply: `salary_components`/`salary_structures` absent; memberships rows present. Post-apply: both tables exist with RLS enabled + no policies, composite FKs live, `memberships_id_tenant_id_key` added, 0 rows in each new table, 0 seed rows.
