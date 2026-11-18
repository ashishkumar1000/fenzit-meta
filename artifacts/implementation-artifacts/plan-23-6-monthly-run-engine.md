# Plan — Story 23-6: Monthly run engine (BE)

- **Status:** built → review (2026-11-18, overnight run 2)
- **Story:** epic-23 id 6 (BE) · CAP-3/5 + Run arithmetic · spec_checkpoint + done_checkpoint (owner confirms fixture numbers before stories 7–9)
- **Oracle:** SPEC.md §Run arithmetic (the invariant) + canonical-fixture.md (money rows verbatim)

## Intent

The async monthly payroll run: population → payable window → LOP from the existing day-status engine → earnings per the single pay formula → deduction assembly (heads + PF + TDS + overrides) → the flat 50% cap with recovery roll-forward → payslip snapshot rows with gap-free slip numbers. Queued→running→completed|failed status machine, advisory-lock serialization, atomic per tenant-month, idempotent re-run (destroy and replace). Zero RPC.

## The window decision (recorded for the done_checkpoint)

The fixture's asserted day-counts reconcile under ONE rule — verified against every row:
**Payable window = employment window ∩ ((M−1's post-cut-off dates) ∪ (all of month M)), capped at the divisor keeping the EARLIEST dates; LOP/day-status attribution follows date OWNERSHIP (d ≤ cutoff(owning month) → that month's run; d > cutoff → next month's run as prior-period).**

- Base A Oct: window Sep 26–30 + Oct 1–31 = 36 → cap 26 → kept Sep 26–30 + Oct 1–21; LOP Oct 12–15 inside → paid 22.5 → earnings 24,230.77 ✓ net 21,953.85 ✓.
- Divisor table: fixed-30 → 30 kept (Sep 26–30 + Oct 1–25) → paid 26.5 → 24,733.33 ✓; calendar → 31 kept → paid 27.5 → 24,838.71 ✓ (both need the full-month window).
- Variant C (join Oct 20): Oct 20–31 = 12 ✓ (the ownership-truncated window would give 6 — contradicts the fixture); E 30→26 ✓; I 29→26 ✓; November A: Oct 26–31 + Nov 1–30 = 36 → 26 kept Oct 26–31 + Nov 1–20 → LOP Oct 27 inside ✓ 29,615.38 ✓.
- **Deviation flagged for the owner:** the fixture's §Effective-dating September row says "payable = min(25,26) = 25"; under the reconciling rule September = 30 days → cap 26 → payable 26. The ASSERTED number (PF 1,800.00, ceiling binds) is identical either way (min(20,000,15,000) = min(19,230.77,15,000) = 15,000). The journey asserts PF 1,800.00, not the day-count.
- Consequence noted: a mid-month joiner (C) is paid their post-cut-off days by October's run AND November's window includes them again — inherent to the fixture's own C=12; surfaced for the owner's confirmation.

## Schema (migration 20261118000000_payroll_run_tables.sql)

- `payroll_runs` — id uuid pk, tenant_id fk, month text not null, status check (queued|running|completed|failed), initiated_by uuid, started_at/finished_at timestamptz, summary jsonb not null default '{}', error_message text, timestamps. Index (tenant_id, month, status).
- `payroll_payslips` — id uuid pk, tenant_id, membership_id uuid not null, user_id uuid not null, run_id fk→payroll_runs, salary_period text not null, slip_number text not null, employee snapshot columns (employee_name, employee_code, father_name, mother_name, spouse_name, designation, department, pan, uan_number, bank_account_number, ifsc_code, bank_name, date_of_joining date), establishment_name text, wage_period_start/end date, divisor_convention text, cutoff_day int, pay_date int, payable_days numeric(6,2), lop_days numeric(6,2), paid_days numeric(6,2), gross_earnings numeric(18,2), pf_employee numeric(18,2), pf_employer numeric(18,2), tds numeric(18,2), other_deductions numeric(18,2), total_deductions numeric(18,2), net_wages numeric(18,2), earning_lines jsonb, deduction_lines jsonb, warnings jsonb default '[]', timestamps. unique (tenant_id, salary_period, membership_id). RLS deny-by-default; service_role only.
- `payroll_run_overrides` — tenant_id, membership_id, month text, field text check (in ('pf_employee','tds')), amount numeric(18,2) check ≥ 0, acknowledged boolean not null check (acknowledged), created_by, timestamps. unique (tenant_id, membership_id, month, field). RLS idem.
- `payroll_recovery_lines` — id uuid pk, tenant_id, membership_id, month_raised text, original_amount numeric(18,2), outstanding_amount numeric(18,2) check ≥ 0, timestamps. RLS idem.
- `payroll_slip_sequences` — tenant_id, salary_period text, last_seq int not null default 0, PK (tenant_id, salary_period). RLS idem.

## Code map

- `src/payroll/run-window.ts` (NEW pure) — employmentWindow(member, month, cutoffOf): owned prior-period dates + month dates; capPayable(days, divisor) keep-first; ownershipOf(date, month, cutoff) → 'owning'|'next'. Unit-tested against the fixture's day-counts.
- `src/payroll/run-lop.ts` (NEW pure) — assembleLop(dates, statuses, unpaidFullDates, unpaidHalfDates, overrides): one source per date, override > unpaid leave > absent; returns { lopDays, warnings } (checkout_missing, enrolment-gap flags).
- `src/payroll/run-math.ts` (NEW pure) — earnings(structure, divisor, paid), earnedBasic(basicAmount, divisor, paid), capClamp(lines, gross) → { clamped, excess }, tdsProjection(structure, monthsEmployed, fyRemaining, priorTds) using statutory.ts.
- `src/payroll/payroll-run.service.ts` (NEW) — POST validation + enqueue (month key 400; before-bound/future/pre-cut-off 422 plain-English; existing queued/running returned; stale-running reclaim), GET status/list. Controller `payroll-run.controller.ts` (@Can('payroll.config'), ParseUUIDPipe).
- `src/payroll/payroll-run-engine.service.ts` (NEW) — the executor: mark running → snapshot all config (calendar/heads/pf/ceiling/structures/population) → per-employee compute (readDayStatusGrid + computeDayStatus + unpaid-leave JOIN + overrides) → ONE write tx (advisory xact lock hashtextextended('payroll-run:'||tenant||':'||month), re-check status, destroy-and-replace payslips, slip numbers via payroll_slip_sequences ON CONFLICT ... RETURNING last_seq, recovery roll-forward, run completed) — failures mark the run failed with the reason, zero payslip changes.
- `src/payroll/payroll-run-override.service.ts` (NEW) + routes — PUT {month, field, amount, acknowledgedLiability:true} (ack false → 422 naming employer liability; unknown field 422), GET per employee+month. Immutable after lock lands with story 9.
- Module wiring; audits `payroll.run_completed` / `payroll.run_failed` / `payroll.run_override_set` via the shared helper.
- **No new DB functions/triggers** — advisory lock via raw `select pg_advisory_xact_lock(hashtextextended(...))` inside withTransaction (existing idiom, AD-3 honored).

## Engine decisions (pinned here)

- Population: role='employee' AND status='active', deduped by user_id; missing join_date → skip 'missing_join_date'; no effective structure → skip 'not_configured'; every window date untracked → skip 'never_enrolled'; empty window → skip 'empty_window'. Skips land in run.summary — never a silent ₹0 payslip; a resolved zero-amount structure is a legitimate ₹0.00 payslip.
- LOP: override(absent 1.0 / half_day 0.5 / present 0) > approved unpaid leave (full 1.0 / half 0.5) > day-status absent 1.0; paid-typed leaves and half_day_leave-with-paid-type contribute 0; checkout_missing and not_tracked-inside-a-partially-tracked-window are paid + flagged; LOP counted only inside the kept (capped) set.
- Earnings = structure ÷ divisor × (payable − LOP), unrounded intermediate, roundMoney once; earned basic = evaluated basic × (payable−LOP)/payable? NO — earned basic = basic ÷ divisor × (payable−LOP) (linear, same value, unrounded intermediate); gross = structure ÷ divisor × (payable−LOP). Every basis clamps at zero before PF/TDS/heads.
- PF: covered = everMember || (switch && !excluded); 12% × min(earned basic, resolved ceiling); employer share recorded not deducted.
- TDS: monthsEmployed = join-month..min(exit-month, FY-end) within FY 2026-27 (never the post-LOP gross); remaining = FY-end − run month + 1 (≥1); prior TDS = sum of the employee's payslip tds in FY months < M; re-spread = annualTax(structure × months − 75,000).total − prior over remaining. A leaver's final run: monthsEmployed ends at exit month (the full remaining estimate lands on the exit-month run naturally).
- Cap: 50% × post-LOP gross (earning lines set = run earnings only until off-cycle lands); checked AFTER overrides; breach clamps the deduction lines PROPORTIONALLY (half-up per line, residual on the largest) and raises the excess as a recovery line (outstanding roll-forward, oldest absorbed first, subject to the same cap).
- Overrides: fields 'pf_employee' | 'tds' (v1; the fixture exercises TDS); replace the computed amount; survive unlocked re-runs; acknowledgment required at save.

## Journey legs (~12, money verbatim)

Seeding: attendance settings/office/enrolment for the run employees; punches (IST timestamps) for worked days; typed leaves for A (2 paid Oct 6–7, unpaid half Oct 12, unpaid Oct 13–15) and the variant employees; the 23-5 Insurance head CHANGED to 2% (save '2' → '2.00') so variant D's 484.62 is exact.

1. October run for the fixture tenant: base row — A payslip PF 2,076.92, TDS 0.00, PT 200.00, gross 24,230.77, net 21,953.85; slip PS-2026-10-0001; payable 26, LOP 3.5, paid 22.5 (DB row asserts).
2. Variant D: override TDS 12,000 (ack) → re-run → deductions 14,761.54 clamped 12,115.39, net 12,115.38, recovery 2,646.15 raised.
3. September run (before October? no — run September FIRST actually; order: September run asserts PF 1,800.00 (ceiling 15,000 binds)); then October.
4. Variants C (join Oct 20, net 11,615.39), C2 (exit Oct 10, net 9,646.15), E (join Oct 2 + unpaid Oct 5, net 26,923.08), I (join Oct 3 + absent Oct 20 + paid half Oct 10 + pre-join unpaid Oct 1–2, net 24,415.39).
5. Variant F + November: revision 2026-11-01, leave Oct 27 seeded after October's run, run November → LOP 1.0 prior-period, net 26,876.92, October payslip unchanged.
6. Owner-corrected half-day: override Oct 21 half_day → re-run → LOP 4.0, net 21,461.54 (the half-day deduction 538.46 = half the daily wage).
7. Divisor conventions: set fixed-30 → run → 22,413.33; calendar → run → 22,509.68; back to fixed-26.
8. G edges: otherTenant zero-employee run → completed, no_employees, zero payslips; not_configured skip (memberE); owner + removed memberC structures excluded; missing-PAN employee → blank + warning; checkout_missing day paid + flagged (a record with checkin only); never-enrolled skip (an employee with no enrolment).
9. Cut-off re-scoping: set cut-off 20, run October → the Oct-22 leave lands in November's run.
10. Rejections: 2026-08 (before bound), 2026-12 (future), November pre-cut-off attempt (current month, today < 25) — each 422 plain-English, zero payslips.
11. Status machine: GET run status polling queued/running→completed; failed run is terminal and retryable.
12. Idempotent re-run: October re-run (no changes) → same numbers, one payslip per employee, new slip numbers (regeneration), old rows destroyed.

## Acceptance criteria

Every asserted money row traces to canonical-fixture.md verbatim; `bun run test`, typecheck, lint, journey green except the sync/users baseline; the September payable-25 deviation documented for the owner.

## Verification

Unit: run-window/run-lop/run-math specs (fixture day-counts + cap clamp + TDS projection). Journey: the legs above. Full suite: baseline reds only.

## Plan Change Log

## Review Triage Log

## Implementation Notes

## Review Triage Log

### 2026-11-18 (BMAD thorough: edge-case-hunter + verification-gap; triaged per the always-triage rule)

**Code review complete.** 0 decision-needed, 12 patch, 2 defer, 5 rejected. Every finding verified at source before a verdict.

- [x] [Review][Patch] Two racing enqueues could both complete a month (no active-run uniqueness; the write-tx re-check read only its own row) — APPLIED: partial unique index `payroll_runs_one_active_per_month` + the insert's 23505 → idempotent winner-return + the write-tx re-check refuses when another run for the month is still active.
- [x] [Review][Patch] The advisory lock was per tenant-month — adjacent months' concurrent runs could double-debit a recovery line — APPLIED: the lock is TENANT-wide.
- [x] [Review][Patch] A queued run whose executor died before claiming stayed queued forever (the reclaim covered running only) — APPLIED: the stale reclaim covers queued (created_at-based) too.
- [x] [Review][Patch] The failed-marking had no status guard (a late failure could clobber a completed row) and error_message could carry raw DB text — APPLIED: `.eq('status','running')` + a plain-English allow-list with a generic fallback.
- [x] [Review][Patch] A post-cut-off joiner (no owned LOP dates) was wrongly skipped never_enrolled — APPLIED: trackedAny consults the payable window as well.
- [x] [Review][Patch] Recovery absorption matched positionally over the re-sorted clamp lines (crossed outstanding debits) — APPLIED: matching by the baked `recovery:<month_raised>` source.
- [x] [Review][Patch] A re-run with the cap still breached inserted duplicate recovery rows — APPLIED: the write tx replaces the month's raised recoveries (idempotent).
- [x] [Review][Patch] The payslip's pf/tds columns stored pre-clamp values, disagreeing with the clamped lines/totals — APPLIED: the snapshot's statutory columns read the CLAMPED lines (the D leg's tds assert updated: the ₹12,000 override deducts 9,848.88 under the cap).
- [x] [Review][Patch] Recovery lines orphaned on membership delete — APPLIED: composite FK cascade (migration 20261118010000; 235 orphan rows from failed journey runs purged first).
- [x] [Review][Patch] 'the 1th/22th' ordinal copy in the pre-cut-off refusal — APPLIED: "day N of the month".
- [x] [Review][Patch] The LOP-shortfall warning promised a recovery that is never written — APPLIED: reworded to the off-cycle correction.
- [x] [Review][Patch] Coverage: the failed-path leg (corrupt structure → failed, zero payslip changes, plain-English error, clean retry), the pf_employee override through a run (1,000.00 mirrored to the employer share), the empty_window + not_configured + missing_join_date skip asserts, the runs list, the cross-tenant run 404, the override bad-field 422 — APPLIED (53 legs).

**Rejected** (with refutations):
- "Resolved cutoff day 1-3/21-23 produces 'the 1th'" — superseded by the copy patch above.
- "divisor_convention outside the enum silently prices fixed-26" — false: the calendar column's CHECK (20261117200000) makes it unreachable.
- "Two racing executors both write the month" (the engine re-check) — the re-check now refuses on any other active run for the month + the partial unique prevents two active rows.
- "The stale-reclaim's 0-row update unnoticed" — the follow-up insert IS the correct retry behavior.
- "payroll_run service tenantToday '' refuses everything" — the tenant exists (FK) and its timezone is trigger-guarded; unreachable.

**Deferred** (ledgered in deferred-work.md): the two-run cut-off re-scoping leg (the pure ownership test + the November prior-period leg cover the wiring); FY-2026-27 slabs past 2027-03 (a run beyond the FY is a future-month rejection until the FY config ships).

**Verification after all patches:** 289/289 payroll unit tests, 53/53 journey legs, typecheck clean, 0 lint errors, full suite at the sync/users baseline reds only.

## Implementation Notes

- **The window decision (reconciled during the build):** payable = employment ∩ month (capped keep-first at the divisor); LOP attribution = date OWNERSHIP (month dates ≤ cut-off + the prior month's post-cut-off dates ∩ employment, uncapped). This is the ONLY rule that satisfies every fixture row (C 12, C2 10, E/I 26, base 26/3.5, calendar 31, fixed-30 30, November 26 with the Oct-27 prior-period LOP). The ONE fixture divergence: September's "payable 25" text (the rule gives 26) — its asserted number (PF 1,800.00, ceiling binding) is identical either way. FLAGGED for the owner's done_checkpoint.
- **Rounding divergence (flagged):** November's gross 29,615.39 = the SUM of the rounded earning lines (the spec's rounding-once-per-line); the fixture's 29,615.38 shorthand rounds the structure total once. One paise — the owner adjudicates at the done_checkpoint.
- **The D-leg tds column reads the CLAMPED value (9,848.88 of the ₹12,000 override)** — the snapshot agrees with what was actually deducted.
- Journey fixture facts seeded for the run world: attendance settings/office/enrolments (enabled_at backdated to 2026-09-01 so the enable-day grace doesn't untrack), weekly-off defaults ([7] = Sunday), punches for every owned date (an unpunched owned day grades absent and LOPs), typed leaves (the 23-2 catalog re-typed: Casual unpaid for Oct 13–15, Earned paid re-typed for Oct 6–7).
- The engine's `void executeRun` is fire-and-forget from enqueue; a wedged executor is reclaimed by the next POST for the month (stale past 15 min).
