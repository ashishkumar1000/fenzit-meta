---
title: 'Epic 23 story 1 — Employment data for payroll (BE)'
type: 'feature'
ticket: '23-1'
created: '2026-11-17'
status: 'in-progress'
route: 'full'
route_source: 'auto'
baseline_revision: '65091b2'
review: ''
review_source: ''
lenses_ran: []
review_loop_iteration: 0
context:
  - 'artifacts/specs/spec-payroll/canonical-fixture.md'
  - 'artifacts/specs/spec-payroll/SPEC.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Payroll cannot exist — memberships carry no employment data (join/exit dates, PAN, DOB, Form V names, PF/UAN, bank, designation, department) and the tenant employee code is auto-assigned only (owner cannot set or edit it, CAP-13).

**Approach:** One DDL migration adds the CAP-13 field set to `memberships` and backfills join dates (from `created_at` in tenant tz) and removed-membership exit dates (from `audit_log` `member.remove`, clamped ≥ join, never inverted). NestJS-only GET+PATCH `/members/:userId/employment` (company-admin-only) owns validation and the owner-set employee code. New real-DB journey suite `test/payroll-journey.e2e-spec.ts` seeded from canonical-fixture Employee A verbatim.

## Boundaries & Constraints

**Always:** Zero new RPCs — DDL migration + NestJS only (AD-3). All new fields on `memberships` (deny-by-default RLS), never `users` (users carries legacy JWT-claim policies). New columns stay OUT of `listCompanyMembers`' select, `CompanyMember`, the technician roster, and `GET /me` — DOB/PF/UAN/bank never reach other employees. Explicit `.eq('tenant_id', caller.tenantId)` on every read/write. exit ≥ join enforced service-side in plain English, DB CHECKs as backstop; join date clearable (that IS the run's skip path); exit-without-join rejected (judged on the post-write state — clearing join + setting exit in one PATCH rejects). Service maps DTO fields to columns explicitly (never spreads the DTO into `.update()`); unique-violation `23505` on `memberships_tenant_employee_code_key` mapped to 409. Audit `details` carry changed-field names + old/new employee_code only — no PAN/DOB/bank duplicated into audit_log. Backfill never invents PAN/DOB/UAN.

**Never:** No web/mobile UI (stories 10–12). No leave-type catalog (story 2). No payroll run logic. No new SECURITY DEFINER functions. No UAN/bank format invention beyond length caps (spec mandates only PAN, IFSC, exit≥join validation).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Full Form V save | admin PATCHes all CAP-13 fields for Employee A | 200; every column persisted; audit row written | — |
| exit < join | exitDate 2026-09-01, joinDate 2026-10-01 | rejected | 422, plain English |
| exit without join | joinDate null/absent, exitDate set | rejected | 422 |
| invalid PAN | `12bcd345g` | rejected | 422 `[A-Z]{5}\d{4}[A-Z]` |
| invalid IFSC | `HDFC12XY34` | rejected | 422 4 letters + 7 alphanumeric |
| clear join date | joinDate null, no exit set | allowed (skip path stays real) | 200 |
| clear join + set exit same request | joinDate null, exitDate set | rejected (post-write state) | 422 |
| clear employee code | employeeCode null | rejected — code is permanent | 422 |
| invalid calendar date | joinDate `2026-02-30` | rejected (real parse, not regex only) | 422 |
| edit removed membership | PATCH exit date on a `removed` row | allowed — the flagged-exit fix path | 200 |
| employee code conflict | code already used by another membership | rejected naming the conflict | 409 |
| non-admin calls | employee/viewer token | forbidden | 403 |
| cross-tenant userId | admin of tenant B reads tenant A member | not found | 404 |

</frozen-after-approval>

## Code Map

- `workspace/core/backend/fenzit-be/supabase/migrations/20261020000001_roles_new_structure.sql:59-103` -- memberships schema, RLS enabled + revoked from anon/authenticated (no column work needed for RLS), audit_log + append-only trigger.
- `.../20261020000003_roles_rewrite_to_memberships.sql:1061-1086` -- `set_employee_code()` is INSERT-only; UPDATE unguarded → owner-edit is a plain guarded UPDATE, no trigger change.
- `.../20261020000005_roles_review_fixes.sql:342-347` -- remove flow: status flip + audit action `member.remove` with `target_user_id` = the backfill's exit-date source (no status_changed_at column exists).
- `.../20261112000001_employee_job_settings.sql` -- newest member-column migration; audit old/new details + skip-when-no-change idiom to copy.
- `src/common/members/company-members.ts:72-137` -- `listCompanyMembers`/`findCompanyMember`: explicit select lists; do NOT extend with new fields.
- `src/members/members.controller.ts` -- route + `@Can()` + `ParseUUIDPipe` patterns; `src/common/permissions/permissions.ts:12-100` -- Permission union + ROLE_PERMISSIONS (`member.job_settings` sits outside ADMIN_PERMISSIONS — copy that placement).
- `src/members/dto/` -- DTO idiom: `@ApiProperty` + per-field plain-English messages; `@Matches` precedent in `src/auth/dto/setup-company.dto.ts:35,46` (GSTIN); validation failures surface as 422 via global pipe (`src/common/validation-pipe-options.ts`).
- `src/members/members.service.ts:337-348,372-430` -- admin-client usage, `mapError`, audit read; `src/customers/import/import-commit.service.ts:237-244` -- app-side `write_audit_row` precedent (existing RPC, not a new one).
- `src/users/users.service.ts:315-316,342-343,434-452,529-556` -- `/me` + roster explicit whitelists; leave untouched.
- `test/attendance-journey.e2e-spec.ts:32-135,457-468` -- journey precedent: real-DB gate, AppModule + ValidationPipe bootstrap, throwaway tenant/users/memberships inserts, `purgeCompanyChildren` cleanup, order tenants→users last. Helpers: `test/helpers/attendance-company-fixture.ts`, `test/helpers/auth-test-utils.ts:26-28` (locally minted JWT).
- `test/jest-e2e.json` + `test/jest.env.setup.ts` -- e2e config (maxWorkers 1, env defaults, real-DB gating).
- Tenant tz: `tenants.timezone` (default `Asia/Kolkata`); conversion `(timestamptz AT TIME ZONE tz)::date`.

## Tasks & Acceptance

**Execution:**
- [ ] `supabase/migrations/20261117100000_membership_employment_data.sql` -- ADD COLUMNS join_date/exit_date/pan/date_of_birth/father_name/mother_name/spouse_name/pf_account_number/uan_number/designation/department/bank_account_number/ifsc_code/bank_name (all nullable; text cols length-capped) + CHECKs (exit≥join; exit requires join; PAN/IFSC shape when non-null) + column comments; set-based backfill: join_date = created_at date in tenant tz for all rows; exit_date = latest `member.remove` audit date **iff that date ≥ the backfilled join** (clamp in the UPDATE's WHERE — CHECK can never trip), otherwise NULL (unclampable, flagged); record unclampable list as artifact -- the data model (spec_checkpoint).
- [ ] Apply migration via Supabase MCP (project `pnlvreaijzslfymlnoti`) -- no live users, so apply anytime; pre-apply sample SELECT verifying the tz conversion on a boundary row + counts (memberships total, removed count vs distinct `member.remove` audit targets) recorded in Implementation Notes; post-apply spot-check zero-NULL join + removed exit≥join.
- [ ] `src/common/permissions/permissions.ts` -- add `member.employment` to the union; grant to `company_admin` only, outside ADMIN_PERMISSIONS.
- [ ] `src/members/dto/update-employment.dto.ts` -- all-optional DTO; `@Matches` PAN/IFSC + `yyyy-mm-dd` dates; null = clear, absent = untouched; plain-English messages.
- [ ] `src/members/members.service.ts` -- `getEmployment` (full CAP-13 select incl. employee_code) + `updateEmployment` (read membership directly by user_id+tenant_id any-status — NOT `findCompanyMember`, which filters removed → 404; trim text and empty-after-trim = clear; validate exit/join rules against the post-write state → 422; employee_code uniqueness probe AND `23505` mapping → 409 naming conflict; explicit field-by-field `.update()` payload — never spread the DTO; static error messages, no PAN echo; audit via `write_audit_row` action `member.employment_update`, details = changed-field names + old/new employee_code only, skip when nothing changed).
- [ ] `src/members/members.controller.ts` -- GET + PATCH `/members/:userId/employment`, `@Can('member.employment')` + `ParseUUIDPipe`.
- [ ] `src/members/members.service.spec.ts` -- unit tests: validation order, conflict mapping, no-op audit skip, null-clear semantics.
- [ ] `test/payroll-journey.e2e-spec.ts` -- create suite (attendance-journey helpers): throwaway tenant + owner + Employee A membership; seed Employee A Form V verbatim (code EMP-001, Field Technician, Field Operations, DOB 1995-04-12, father Ramesh Sharma, PAN ABCPE1234F, UAN 101234567890, PF PY/ABC/12345/000, bank 1234567890, IFSC HDFC0001234, HDFC Bank, joined 2026-09-01); legs: full save → DB assert every column; exit<join 422; invalid PAN 422; invalid IFSC 422; cross-tenant read 404; clear join ok; exit-without-join 422 (also in the same request as join clear); clear employee code 422; invalid calendar date 422; PATCH exit on a removed membership 200; code conflict 409; employee token 403; audit row present; removed-membership exit backfill clamp asserted at SQL level.
- [ ] Backfill probe: local server + production probe of GET/PATCH; record the unclampable-rows list (expected zero — memberships and audit_log were born the same day) in this plan's Implementation Notes.

**Acceptance Criteria:**
- Given a company_admin, when PATCHing the full CAP-13 set for a member of their tenant, then 200 and every column round-trips via GET; audit_log gains exactly one `member.employment_update` row; a repeat identical PATCH writes no audit row.
- Given any member list/roster/`/me` response, then none of the new columns appear (privacy invariant holds by construction).
- Given the migration applied, then every existing membership has join_date = its created_at date in tenant tz; removed memberships have exit_date = their member.remove audit date when ≥ join; unclampable rows are NULL and listed, never inverted.
- Given the I/O matrix scenarios, each behaves as specified (422/409/403/404 as listed).
- Given `bun run test` and `bun run test:e2e` (real-DB env), then all suites green; the new journey suite passes end to end against the real DB.

## Implementation Notes

- (build agent, 2026-11-17) Migration `membership_employment_data` applied via Supabase MCP, project `pnlvreaijzslfymlnoti`, exactly as the file `20261117100000_membership_employment_data.sql`. **Pre-apply probes:** memberships total **160**; removed memberships **0**; distinct `member.remove` audit targets **0** (0 audit rows); tenants 20, all `Asia/Kolkata`. Tz-conversion boundary probe: **49/160 rows** cross the IST midnight (sample: created 2026-09-06T18:36:44Z → tz date **2026-09-07**; created 2026-09-07T19:36:44Z → **2026-09-08**) — conversion verified before apply. **Post-apply:** `join_date is null` count **0** (all 160 backfilled, join range 2026-09-01..2026-11-14); removed rows with exit < join **0**; **unclampable-rows list = [] (zero)** — expected, since memberships and audit_log were born the same day and no membership has ever been removed on this project.
- (build agent, 2026-11-17) Backfill scope decision: the exit backfill targets only `status = 'removed'` rows. The plan says "removed-membership exit dates"; a re-invited row (status back to invited/active) is an ongoing employment — writing its historical remove date as `exit_date` would wrongly end the current employment window in payroll. Left NULL there instead.
- (build agent, 2026-11-17) Audit write follows the plan's cited precedent (`import-commit.service.ts`): a failed `write_audit_row` logs and moves on — the member's save stays; PostgREST cannot make update+audit atomic in one call (the RPC-based flows get same-step atomicity only because the function writes both).
- (build agent, 2026-11-17) Caught by the new unit spec before any real data was touched: `pan` was initially missing from the DTO→column field map (it would never have persisted). Fixed; the "full Form V save" test now asserts every column.
- (build agent, 2026-11-17) Journey-suite clamp leg replays the migration's two backfill UPDATEs scoped to its two subject rows. Reason: the shipped migration ran once over rows that were all exit-NULL, but a replayed tenant already holds API-set exits — a full-tenant replay of backfill step 1 would set a join date after an existing exit and trip the `memberships_exit_not_before_join_check` CHECK. This is a replay artifact, not a migration flaw.
- (build agent, 2026-11-17) A first journey run crashed before `beforeAll` (JWT minted at describe scope; fixed by minting per call) and left throwaway rows: tenants `68b2c7a1-8dfb-43b8-bbc4-f201a45b3d6b` ("payroll journey 68b2c7a1", 6 audit rows) and `8f616f8e-0f50-44c0-9f62-fd6c2b690d12` ("payroll stranger 8f616f8e"), plus 6 users named "payroll journey 0..5" (memberships were purged). The MCP destructive cleanup (append-only-trigger-off delete) was declined by the owner, so the rows remain — harmless pre-launch test data, listable by those ids. The suite now cleans its own audit rows via the house idiom `deleteAuditRows` (`test/helpers/rls-seed.ts`) in `afterAll`, so future runs leave nothing.
- (build agent, 2026-11-17) Verification tallies. **Unit** `bun run test`: 165 suites — 163 pass, 2 fail (`src/sync/sync.service.spec.ts`, `src/users/users.service.spec.ts`); 2859 tests — 2853 pass, 6 fail. Both failing suites were verified red on the baseline (git stash → run → pop): pre-existing, not from this story. Members suites: 90/90 green (incl. the new employment + DTO blocks and the controller permission-table rows). **E2e** (real DB, `node --env-file=.env jest --config ./test/jest-e2e.json`, the `test:e2e:real` idiom since jest needs plain node): 47 of 63 suites ran, **`test/payroll-journey.e2e-spec.ts` passes 13/13 legs**; 13 suites fail (rls-isolation, attendance-journey, auth.integration, attendance, attendance-corrections, attendance-reads, attendance-check-in-out.integration, customers, jobs, sync, reports-retry, notifications, users) — all 13 verified failing identically on the baseline (same 142 test failures without my change): pre-existing red, untouched by this story. **`bun run build` and `tsc --noEmit`: clean.** Lint (eslint): all new files clean; `members.service.ts` / `members.controller.spec.ts` carry only the unsafe-assignment / unbound-method errors their baseline versions already had (verified via stash).
- (build agent, 2026-11-17) Correction to the tally above: the employment describe held **16 it() cases** at review time, not 20 as first reported (the 5 DTO tests were correct as stated). The code-review patches add four more (audit resolves-with-error, audit rejects, PGRST116 → 404, 23514 → 409), bringing the employment describe to 20 it() cases.

## Plan Change Log

## Review Triage Log

## Design Notes

- **Fields live on `memberships`, not `users`**: users still carries legacy JWT-claim RLS policies (leak risk for DOB/PAN/bank); memberships is deny-by-default with service-only access, and Form V data is per-employment anyway. Same person in two tenants gets per-tenant copies — acceptable pre-launch, matches the payroll-FK-through-memberships contract.
- **Employee code in the same PATCH**: one save surface for the whole Form V form (web story 10); uniqueness conflict surfaces as 409 naming the colliding code. Auto-assign on invite stays untouched.
- **Clearing semantics**: `joinDate: null` in body clears; absent key untouched (`@IsOptional` skips null+undefined) — JSON null is the clear verb, matching "clearing the join date is allowed".
- **Test-timing note**: CLAUDE.md gates tests behind user confirmation, but the epic contract (committed stories.yaml, fixture-anchored e2e) mandates the journey suite in-story — it is the epic's test oracle; unit spec co-located per house style.
- **No live users in production** (owner, 2026-11-17): migration applies anytime — no quiet-window or lock-windowing needed; the backfill operates on test data, but its semantics (clamp, flag, never invert) stay real-data-correct for launch.
- **Trim/empty contract**: text fields trimmed on save; empty-after-trim stores NULL (a clear). `employeeCode` is the only non-clearable field.
- **Epic cadence (owner, 2026-11-17)**: per story — elicitation on plan → implement → BMAD code review → push. Overrides the stories.yaml "review batched at epic end" note.

## Verification

**Commands:**
- `bun run test` (fenzit-be) -- expected: all unit suites green (incl. new members.service tests).
- `bun run test:e2e` -- expected: real-DB suites green incl. `payroll-journey.e2e-spec.ts` (needs DATABASE_URL/SUPABASE_* real env, per its gate).
- `bun run build` or lint script if present -- expected: clean.

**Manual checks (if no CLI):**
- Post-migration SQL probe: `select count(*) filter (where join_date is null) from memberships` → 0; removed rows' exit ≥ join everywhere.
- (orchestrator, 2026-11-17) Leftover purge done with owner consent: 2 tenants, 6 users, 6 audit rows deleted via the house `session_replication_role = replica` idiom over the direct pg connection (MCP cannot express it; MCP `disable trigger all` fails on system RI triggers). Post-purge MCP verification: tenants/users/audit all 0.

## Code Review

### 2026-11-17 (thorough: blind-hunter, edge-case-hunter, verification-gap, intent-alignment)

**Code review complete.** 0 `decision-needed`, 8 `patch`, 0 `defer`, 13 `rejected`.

- [x] [Review][Patch] Audit-write rejection uncaught + audit-failure branch untested [src/members/members.service.ts:699-714] — the rpc await has no try/catch, so a network rejection fails the PATCH after the UPDATE committed, breaking the stated "audit failure must not undo the save" contract (import-commit precedent wraps it); no test drives the audit-error branch (buildEmployment hardwires rpc success). Fix: try/catch + two tests (resolved error, rejected promise) per import-commit.qa.spec.ts:369-381.
- [x] [Review][Patch] Unmapped update-error codes answer opaque 500s [src/members/members.service.ts:656-670] — a member deleted between read and write (.single() → PGRST116) and a CHECK-race 23514 (stale read: another admin moved join_date between this read and write) both surface as "Failed to save the employment record" 500. Fix: map PGRST116 → 404; 23514 → 409 "changed since read — reload".
- [x] [Review][Patch] Dropping the member.employment grant fails no normal-path test [src/common/permissions/permissions.ts:97] — only the real-DB journey would notice; controller/service/guard specs all pass with the grant gone (verified: zero grep hits pinning the grant). Fix: job-settings.spec.ts:165-182-style pins (COMPANY_ADMIN positive; EMPLOYEE/VIEWER/PLATFORM_ADMIN negative) in the employment describe.
- [x] [Review][Patch] Backfill clamp leg asserts a hand-copied replay, never the migration file [test/payroll-journey.e2e-spec.ts:480-559] — the inline pool.query statements are a typed copy; editing the migration's backfill (e.g. dropping `m.status = 'removed'`, max→min) breaks nothing. Fix: the leg reads the two UPDATE statements from the migration file and executes them verbatim inside a rolled-back transaction, asserting on the seeded rows before rollback.
- [x] [Review][Patch] Migration comments promise a flag that does not exist / understate exit-on-active [supabase/migrations/20261117100000_membership_employment_data.sql:31-33,44-45] — "left NULL and flagged" has no in-DB flag (the flag is the apply-time probe list); exit_date comment speaks only of removed memberships while the API correctly allows an active membership to carry exit_date (fixture variant C2 requires exactly that). Fix: reword both comments.
- [x] [Review][Patch] OpenAPI surface incomplete on the new endpoints [src/members/members.controller.ts:133-186, src/members/dto/update-employment.dto.ts] — no 200/@ApiOkResponse(EmploymentView), no 403/400 responses; ApiPropertyOptional fields lack nullable: true so generated clients never send the null-clear verb. Fix: add the response entries + nullable flags.
- [x] [Review][Patch] employmentRowOf returns null typed as a row [test/payroll-journey.e2e-spec.ts:~101] — a fixture miss yields a TypeError at the caller instead of a clear failure. Fix: throw "row missing" with the ids when absent.
- [x] [Review][Patch] Claims tally correction [plan Implementation Notes] — the employment describe holds 16 it() cases, not 20 as the report said (5 DTO tests is correct).

**Rejected appendix:**
- IFSC/PAN shapes weaker than real-world formats [blind-hunter] — false: the spec pins exactly these shapes ("IFSC 4 letters + 7 alphanumeric", PAN 5+4+1); DB CHECKs mirror the DTO; tightening would edit the approved contract.
- No semantic date bounds (future DOB, year 0001) [blind-hunter] — rejected low: not in the mandated contract; web date picker lands in story 10; adding bounds invents validation.
- UAN/PF/bank free-text vs PAN/IFSC depth [blind-hunter] — false by contract: plan's Never list forbids inventing UAN/bank formats.
- 23505 without a code change would print "undefined" [blind-hunter + edge-case-hunter] — rejected low: unreachable today (the update payload touches only the one unique-constrained column); constraint-name sniffing adds fragile complexity.
- Backfill assigns join_date to 'invited' memberships [blind-hunter] — plan-conformant ("for all rows"); when an invite is activated the owner edits the join date via this very API before any run consumes it; changing the filter would edit the frozen plan. Owner-visible observation: say the word and a follow-up narrows the backfill to active/removed.
- Formatting reflow mixed into the feature diff [blind-hunter + intent-alignment] — rejected low: lint/prettier enforced on touched files; single-dev direct-to-main repo, merge-conflict harm negligible.
- normalisedText TypeError on non-string [edge-case-hunter] — false: the only caller receives the pipe-validated DTO; unvalidated service calls are out of contract.
- EmploymentView.employeeCode null despite string type [edge-case-hunter] — false: memberships.employee_code is NOT NULL with an insert trigger that always assigns.
- CAP-13 editability lives in the web admin [intent-alignment] — divergence is story scope: web stories 10–11 own that surface (E1 reading correct for this BE story).
- Run-side success criteria (proration, skip-warning, blank-PAN warning) [intent-alignment] — later stories: the run engine is story 6; this story pins the data contract only.
- Set-at-creation half of CAP-4 missing [intent-alignment] — false as a divergence: invite_member has accepted caller-supplied codes since 20261020000005:142; the missing half was owner-edit, which this diff adds.
- exit-on-active broader than migration commentary [intent-alignment + blind-hunter] — folded into the comment patch (P5): the code is right (fixture C2), only the comment was narrow.
- Unit mocks encode the service's own call pattern [intent-alignment] — acknowledged descriptive note; the real-DB journey leg covers the same paths end to end.
