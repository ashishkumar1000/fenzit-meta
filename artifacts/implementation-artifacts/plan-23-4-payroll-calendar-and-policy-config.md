---
title: 'Epic 23 story 4 — Payroll calendar and policy config (BE)'
type: 'feature'
ticket: '23-4'
created: '2026-11-17'
status: 'in-progress'
route: 'full'
route_source: 'auto'
baseline_revision: '89dbe01'
context:
  - 'artifacts/specs/spec-payroll/canonical-fixture.md'
  - 'artifacts/specs/spec-payroll/SPEC.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The run engine (story 6) has no month-start-resolved policy to resolve — LOP divisor convention, attendance cut-off day, pay date and the per-state rules-notified overlay flag do not exist, and nothing yet answers "what does month M look like for payroll?" (CAP-4, CAP-8).

**Approach:** Zero new RPCs, consuming the story-3 pure modules. One effective-dated config table `payroll_calendar` (tenant, effective_from, divisor_convention calendar|fixed-30|fixed-26 default fixed-26, cutoff_day default 25 valid 1–28, pay_date default 1 valid 1–7; unique (tenant_id, effective_from); same-date save REPLACES the dated row — the structures idiom) and one per-tenant state table `payroll_state_rules` (tenant PK, notified boolean default false). The month-status API `GET /payroll/months/:month` resolves the calendar row per month-start (the story-3 `resolveEffective`), applies the defaults when no row qualifies, returns `locked: false` while no lock state exists (story 7 adds it), and derives the first-payroll-month bound from active employee-role memberships' earliest join_date — absent or future bounds surface with a plain-English reason, never a silent rejection. Validation: cutoff 29/30/31 → 422 with the February reason; pay date 8+ → 422 with the CoW s.17 reason; month key must be a real 'YYYY-MM'. All behind the existing `payroll.config` permission (company admin only).

## Boundaries & Constraints

**Always:** Deny-by-default RLS + revoke + grant service_role + comments on both new tables. Explicit tenant filter on every read/write. resolveEffective via `src/payroll/effective-dating.ts` (its first production consumer). Service-stamped `updated_at` on real changes (no trigger — zero-functions boundary). Same-date calendar save replaces (upsert on the unique pair, identical-resave no-op like structures). Real-calendar-date validation on effectiveFrom (the story-3 constraint, reused) and a real-month check on the month-status path parameter. Audit every mutation via `write_audit_row` (`payroll.calendar_saved` / `payroll.state_rules_updated`), try/catch'd. The month-status response carries the resolved row's effectiveFrom so the web UI can show what governs the month. Plain-English copy.

**Never:** No run engine, LOP derivation, or money (story 6). No lock machinery — `locked` is part of the response contract from day one and resolves to false while no lock row exists. No payslip/off-cycle/UI. No DB functions/triggers. No new permission (reuse `payroll.config`). No changes to attendance or day-status code (the cut-off here is payroll config only; attendance freeze is story 7's). No per-tenant seed rows (defaults apply at read time when no dated row qualifies).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Month status, no calendar rows | GET /payroll/months/2026-10 | defaults: fixed-26/25/1, locked false, firstPayrollMonth from memberships, runnable true with governing "defaults" marker | — |
| Month status, dated row governs | row effective 2026-10-01 | months/2026-10 resolves the row; months/2026-09 still resolves defaults | — |
| Mid-month-dated change | row effective 2026-11-10 | months/2026-11 does NOT see it (month-start); months/2026-12 does | — |
| Save calendar | PUT {effectiveFrom, divisorConvention?, cutoffDay?, payDate?} | 200; dated view of the saved row | — |
| Same-date save | same effectiveFrom again | replaces the dated row (one row for the date) | — |
| Identical re-save | same values again | no-op: no write, no audit | — |
| Cutoff 29/30/31 | {cutoffDay: 29} | rejected with the February reason | 422 |
| Cutoff 0/32/non-int | {cutoffDay: 0} | rejected | 422 |
| Pay date 8+ | {payDate: 8} | rejected with the CoW reason (before expiry of the 7th day) | 422 |
| Pay date 0 | {payDate: 0} | rejected | 422 |
| Bad divisor | {divisorConvention: 'weekly'} | rejected naming the three conventions | 422 |
| Invented date | effectiveFrom 2026-02-30 | rejected | 422 |
| Bad month key | GET months/2026-13 | rejected | 400 |
| State rules flag | PUT /payroll/state-rules {notified: true} | 200; persisted; audit row | — |
| Read state rules | GET /payroll/state-rules | current flag (false until first save) | — |
| Absent bound | tenant with no employee join dates | firstPayrollMonth null + plain-English reason | — |
| Non-admin caller | employee/viewer/platform-admin token | forbidden | 403 |
| Unknown company caller | token with no tenant | 400 (company setup required) | 400 |

</frozen-after-approval>

## Code Map

- `src/payroll/effective-dating.ts` — resolveEffective/isMonthKey/monthFirstDay, now consumed in production.
- `src/payroll/salary-structures.service.ts` — the same-date-replace + identical-resave-no-op + service-stamped-updated_at idiom to copy.
- `src/payroll/dto/salary-structures.dto.ts` — PayrollCalendarDateConstraint (reuse, do not duplicate).
- `src/attendance/leave-types.service.ts` — audit + probe idioms.
- `test/payroll-journey.e2e-spec.ts` — extend with the calendar legs (otherTenant has a company_admin with NO employee members — the absent-bound leg's seed already exists).
- Migration slot: `20261117200000_payroll_calendar_and_state_rules.sql` (past the concurrent session's 130000 customers migration).

## Tasks & Acceptance

**Execution:**
- [ ] Migration: both tables, checks (divisor enum, cutoff 1–28, pay date 1–7), unique (tenant_id, effective_from), RLS+revoke+grant+comments. Apply via MCP.
- [ ] `src/payroll/payroll-calendar.dto.ts` — PutPayrollCalendarDto (optional fields; null refused), StateRulesDto, views.
- [ ] `src/payroll/payroll-calendar.service.ts` — GET list / PUT save (validation table, upsert+no-op, audit).
- [ ] `src/payroll/payroll-month-status.service.ts` — GET /payroll/months/:month (resolve + defaults + bound derivation + reasons).
- [ ] `src/payroll/payroll-state-rules.service.ts` — GET/PUT flag.
- [ ] `src/payroll/payroll-config.controller.ts` — the three controllers' routes under @Can('payroll.config').
- [ ] Unit specs: calendar validation table, same-date replace/no-op, month-status resolution + defaults + bound reasons, state rules; effective-dating already pinned.
- [ ] Journey legs (~6): defaults, dated-row resolution (Sep stays defaults), mid-month invisibility (Nov vs Dec), February + CoW rejections, state-rules persistence, absent bound via otherTenant.

**Acceptance Criteria:**
- Given no calendar rows, month-status answers the fixture defaults (fixed-26, 25, 1) with locked false.
- Given the fixture's September/October/November/December months, month-start resolution picks the right row each time (unit-pinned + journey).
- Given cutoff 29 and pay date 8, the rejections name February and the CoW 7-day window in plain English.
- Given `bun run test`, `bun run typecheck`, and the journey solo run, then all green except the sync/users baseline reds.

## Design Notes

- **Defaults at read time, not seed rows:** a company that never touches the calendar runs on fixed-26/25/1 — the fixture's base — with zero stored rows; the first save starts the effective-dated trail.
- **`locked` in the contract from day one:** story 7 adds the lock state the flag reads; the web UI (story 11) can render the locked state as soon as it exists without an API change.
- **Bound derivation is a live read:** min(join_date) over active employee memberships — cheap at any headcount with an index that exists (memberships tenant+status), and always truthful to the current data; the run engine (story 6) reuses this same derivation via the service.
- **State rules as its own tenant-PK table:** the flag is a state-of-the-world fact (has this state notified?), not month-effective policy; mixing it into the dated calendar would force every read to disambiguate.

## Verification

**Commands:**
- `bun run test` — expected: baseline reds only (sync, users).
- `node --env-file=.env node_modules/.bin/jest --config ./test/jest-e2e.json test/payroll-journey.e2e-spec.ts` — expected: all legs green.
- `bun run typecheck` — expected: clean.

## Plan Change Log

## Review Triage Log

## Implementation Notes

- **Build state (2026-11-17, pre-review):** migration `20261117200000_payroll_calendar_and_state_rules.sql` applied to Supabase (run-time version 20261117210000); all production code + 3 unit spec files written; payroll module wired; typecheck clean; 158 payroll unit tests green; journey extended 31 → 37 legs, all green.
- **Contract discovery 1 — DTO vs service validation split:** the first journey run caught the DTO's `@Max(28)`/`@Max(7)` intercepting cutoff-29/pay-date-8 BEFORE the service, so the plain-English February/CoW reasons were unreachable through HTTP (generic class-validator text instead). Fix: the DTO keeps only wire-shape guards (`@IsInt` + `@Max(9999)` sanity cap); the service owns every domain refusal (February reason, CoW reason, "between 1 and 28/7", "cannot be cleared"). Lesson: when a story pins plain-English copy on a refusal, that refusal must live BELOW the validation pipe.
- **Contract discovery 2 — full-envelope saves:** a same-date calendar replace is a whole-row replace; absent fields take the DEFAULTS, not the replaced revision's values (pinned by journey leg and a new unit test: replace {cutoffDay 22} on a fixed-30/5 row yields fixed-26/22/1). This matches the DTO copy ("Absent keeps the default") and the codebase's tri-state idiom (absent → default, null → refused). Full-envelope naming restores every field in the same dated slot.
- **Journey fixture facts:** employee A carries join 2026-09-01 (only active employee with a join date — C removed, D/E none), so the main tenant's bound is 2026-09; otherTenant has no employees → no bound + "joining date" reason; stranger-tenant calendar isolation proven both ways (their cutoff 20 vs our 22 for the same month).

## Code Review

### 2026-11-17 (overnight run)

**Code review complete.** 0 decision-needed, 3 patch, 0 defer, 4 rejected. (Two review rounds: 4 ponytail lens agents — correct/safe/fast+lean/tested — plus the BMAD thorough code-review workflow with its edge-case-hunter and verification-gap lenses; all triaged per the always-triage rule, every claim verified at source before a verdict.)

- [x] [Review][Patch] Saving false with no stored row wrote a row and audited a change that never happened [src/payroll/payroll-state-rules.service.ts:64] — APPLIED: absent-row false now returns the read contract answer (false + epoch) with no write and no audit; unit test added.
- [x] [Review][Patch] Invented effectiveFrom was never refused through HTTP on PUT /payroll/calendar — the pipe constraint was unpinned on this route; a regression would answer 500 instead of the pinned 422 [test/payroll-journey.e2e-spec.ts] — APPLIED: journey leg PUT 2026-02-30 → 422 naming effectiveFrom + nothing-written asserts.
- [x] [Review][Patch] The joinsRead.error branch of monthStatus was unexercised — a bound-read DB failure would have answered 200 "Nobody has a joining date yet" [src/payroll/payroll-month-status.service.spec.ts] — APPLIED: mirror unit test using the existing joinsError knob, asserting 500 without DB text and without the setup reason.

**Rejected** (with refutations):
- Concurrent same-date PUTs can double-audit (edge-case-hunter, calendar + state-rules) — verified benign: the upsert serializes on the unique constraint (last-write-wins, idempotent), each write was a real API mutation, the harm is one noise row in an append-only log for a rare double-submit; the proposed conditional-update fix adds complexity for it. The 37-leg journey + audit-count asserts pin the single-caller invariant.
- Non-integer cutoffDay/payDate reaching the service (edge-case-hunter) — false: unreachable; @IsInt + the global ValidationPipe (no implicit conversion) reject NaN/strings/fractions/objects with a 400 before the service.
- Platform-admin 403 not pinned on the three new routes (verification-gap, other) — low: realistic regressions (adding payroll.config to ADMIN_PERMISSIONS, dropping @Can) are caught by the 23-3 staff-token legs on the same permission constant + job-role-grants.spec pins; only a hypothetical per-route decorator swap to a different admin permission would slip.
- (ponytail rounds, recorded for completeness) combined rejection message serves both directions (correct, P4) — cosmetic, phrases already pinned per case.

**Also applied from the ponytail rounds** (before the BMAD pass, all verified then patched): P2 swallowed existence-probe errors in both saves (500 instead of a phantom write); audit details enriched with the stored envelope + previous values; canonicalJson replaced by direct scalar comparison; bound probe switched to DB order+limit(1) with a query-shape tripwire test; month==bound equality pinned; boundary envelope (cutoff 28 / pay date 7) accepted-by tests; null-cleared payDate/divisor it.each rows; save-failure 500s; audit-rpc-resolves-error containment; 403s pinned on all three new routes; divisor trim transform; writeAuditRow helper hoisted (4 services now share one audit rpc contract); monthStatus reads parallelized (Promise.all, 2 RTT → 1 on the hottest config read); unused export/columns trimmed; owner-join-date counterexample in the journey proving the bound's role filter.

**Verification after all patches:** 171/171 payroll unit tests (7 suites), 37/37 journey legs (real DB), typecheck clean, eslint clean on touched files. Baseline reds unchanged (sync/users only).
