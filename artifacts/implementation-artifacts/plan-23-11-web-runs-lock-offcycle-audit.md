# Plan — Story 23-11: Web runs, lock, off-cycle staging and audit (fenzit-web)

- **Status:** plan → adversarial review
- **Story:** epic-23 id 11 · fenzit-web · baseline fa1d2a9 (23-10 shipped, clean tree)
- **Context:** the shipped BE contracts (payroll-run.controller, payroll-config.controller lock pair, payroll-offcycle.controller, GET /payroll/audit, PUT run-override); canonical-fixture.md numbers as the test oracle. Extends the 23-10 payroll page.

## Intent

**Problem:** the owner can configure payroll (23-10) but cannot RUN it, lock a month, stage an off-cycle bonus/recovery, or see the audit trail — every run-shape surface is API-only.

**Approach:** two new tabs on the existing `/admin/company/payroll` page, same URL-owned idiom. **Runs** (`?tab=runs&month=YYYY-MM`, month-centric): the month status card (resolved policy, locked state, first-payable bound, not-runnable reason) with the Run-payroll button; the run card (status machine queued/running/completed/failed with a manual Refresh — RR loaders cannot poll, and a justified `useEffect` poll is deferred, not hacked in); the summary render (employees, payslips, skips with reasons, warnings, offCycle block, recovery block, divisor/cutoff/pay-date); the lock card (completed + unlocked → confirm dialog showing the BE's statement/permanence/remedy + staged lines; locked → the LockView read-only); the staged off-cycle lines for the month (add/edit/cancel dialogs; applied lines read-only); the statutory override dialog (pf_employee/tds with the employer-liability acknowledgment); the runs history list (all months, newest first, failed rows retryable by re-running). **Audit** (`?tab=audit`): newest-first `payroll.*` list with human action labels, actor, target and a compact details read. Zero BE changes.

## Boundaries & Constraints

**Always:** everything from 23-10's Always block (loader-owned data, URL state, native dialogs + fetchers, CSS modules, plain-English "Employee", BE-4xx copy verbatim via the body message, client guards wire-shape only). Off-cycle writes send the optional `x-idempotency-key` header (UUID v4, minted per submit — the BE replays it). The negative-amount acknowledgment is enforced client-side (checkbox required before send) AND owned by the BE. The lock dialog quotes the BE's confirmation fields verbatim — the permanence copy is the product. The summary's money renders through `fmtMoney`; skip reasons map to human lines (missing_join_date → "no joining date on their record", not_configured → "no salary structure for the month", empty_window → "no dates in the payable window", never_enrolled → "never enrolled for attendance"). Runs history caps at what the BE returns (50). Failed runs render the BE's plain-English errorMessage and a "Run again" affordance that re-POSTs the month.

**Never:** no payslip PDF UI (23-12's mobile story owns payslips; an admin payslip surface is a later story); no live polling loop (a Refresh button + navigation revalidation; live polling is ledgered); no unlock affordance anywhere (there is none); no re-implementation of run math — every number comes from the summary; no new shared components beyond what the panels need; no edits to applied off-cycle lines (BE refuses; the UI renders them read-only from the start).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Runs tab, bare | `?tab=runs` | month defaults to the current month; status card renders | failed → retry line |
| Month status | GET months/:month | policy + locked + firstPayrollMonth + notRunnableReason; the reason shows under the button | — |
| Trigger run | POST /payroll/runs {month} → 202 queued | button → "Queued"; card polls via Refresh; completed → summary | 422 not-runnable/before-cutoff/future → verbatim; 409 locked → verbatim |
| Run in progress | GET run → queued/running | status pill + startedAt + "check again" | stale-stuck (BE auto-fails >15 min) shows the failed copy |
| Summary render | completed run | employees/payslips, skips list, warnings list, offCycle {staged, applied, orphaned}, recovery {before/after/raised}, divisor/cutoff/pay-date; zero-employee summary renders "Nobody was on payroll this month" | — |
| Fixture pin | the G November numbers | FE test pins gross 29,615.39 / net 26,876.93 as summary-adjacent rendering | — |
| Lock offered | completed + unlocked | "Lock this month" → dialog with the BE statement/permanence/remedy + staged line list → confirm POSTs | 409 already-locked/run-in-progress/not-run → verbatim |
| Locked month | GET lock → LockView | card renders the confirmation read-only; run button hidden | — |
| Off-cycle list | GET ?month= | staged rows editable (edit/cancel), applied rows read-only with their label | — |
| Stage a bonus | POST {membershipId, month, label, amount>0, tag?} → 201 | row appears; duplicate label 409 verbatim | — |
| Stage a recovery | amount < 0 | acknowledgment checkbox gates Save (client) + BE refuses without it | 422 verbatim |
| Zero amount | amount 0 | blocked client-side with the BE's own sentence | — |
| Edit staged | PATCH tri-state | re-target (membership/month) + label/amount/tag; ack re-asked only for a NEW negative | 409 OFFCYCLE_LINE_CHANGED verbatim |
| Cancel staged | DELETE → 204 | row leaves; applied → 422 verbatim | — |
| Override | PUT run-override {month, field, amount, acknowledgedLiability:true} | compact dialog (employee + field pf_employee/tds + amount + ack checkbox); locked month → 409 verbatim | 422 ack missing → verbatim |
| Runs history | GET /payroll/runs | newest-first; failed rows show errorMessage + Run again; completed rows link to their month card | — |
| Audit | GET /payroll/audit | human labels per action (run completed / month locked / off-cycle staged / override set / component saved…), actor, target, compact details | — |

## Code Map

- `src/features/admin/payrollApi.ts` (EXTEND ~+150 lines) — runs POST/GET/GET:id, months/:month/lock GET/POST, off-cycle GET/POST/PATCH/DELETE (+ idempotency header), run-override PUT, audit GET; views for PayrollRunView/RunSummary/OffCycleLineView/LockView/AuditEntryView.
- `src/features/admin/payrollAction.ts` (EXTEND) — intents `run-trigger` / `lock-month` / `offcycle-create` / `offcycle-update` / `offcycle-cancel` / `override-set`; the off-cycle create/update mint the idempotency key.
- `src/features/admin/payrollLoaders.ts` (EXTEND) — runs tab: month param (validated, defaults to current), parallel { monthStatus, run-for-month (find in GET /payroll/runs), off-cycle lines for month, runs history }; audit tab: settle(audit). LockView fetched when monthStatus.locked.
- `src/features/admin/components/payroll/RunsPanel.tsx` + css (NEW ~380) — month status card, run card + summary, lock card, history.
- `src/features/admin/components/payroll/OffCyclePanel.tsx` + css (NEW ~300) — staged/applied lists + create/edit/cancel dialogs (employee Dropdown, ack checkbox).
- `src/features/admin/components/payroll/OverrideDialog.tsx` + css (NEW ~150) — the statutory override control on the run card.
- `src/features/admin/components/payroll/AuditPanel.tsx` + css (NEW ~180) — the audit list with human labels.
- `src/features/admin/components/payroll/RunSummaryCard.tsx` (inside RunsPanel or its own file if size demands) — the summary render.
- `src/pages/AdminPayrollPage.tsx` (EXTEND) — two tabs + panel delegation; `payrollFormat.ts` (EXTEND) — signed-amount parse for off-cycle.
- Tests: extend `payrollPageKit` (runs/lock/off-cycle/audit fakes + fixture numbers) + `AdminPayrollPage.{runs,offcycle,audit}.test.tsx`.

## Tasks & Acceptance

- [ ] API wrappers + views (runs/lock/off-cycle/override/audit).
- [ ] Loader: month-centric runs fetches + audit; action: six intents with idempotency keys on the off-cycle writes.
- [ ] RunsPanel + RunSummary + lock card + history; OffCyclePanel; OverrideDialog; AuditPanel; page wiring.
- [ ] Kit fakes + tests: wire contracts (POST month body; lock POST; off-cycle POST with idempotency header + ack rule; PATCH tri-state; DELETE; override PUT), summary render pins (fixture G numbers), skip/warning copy, lock dialog quotes the BE copy, applied-line read-only, audit labels.
- [ ] Gauntlet: typecheck/lint/format/styles/design-system/test all green; browser pass against the LIVE BE (reads + at most one safe staged-then-cancelled off-cycle line on the owner's real tenant; NO run trigger and NO lock on the production data — those change real payroll state).

**Acceptance Criteria:** every surface of the matrix reachable owner-only; wire contracts test-pinned (bodies exact, ack rule, idempotency header); the summary renders the fixture's numbers from the BE's own shape; the lock dialog quotes the BE verbatim; the audit list humanizes every `payroll.*` action the BE emits; no polling effect anywhere.

## Design Notes

- **Month-centric runs tab:** the owner thinks in months — status, run, off-cycle lines, lock all answer "what about November?". The month param is shared by every card on the tab.
- **Manual Refresh over polling:** RR loaders are the data layer and effects are banned in features; a "Refresh" button revalidates honestly. A live poll needs a justified effect — ledgered, not hacked.
- **BE copy is the product:** the lock confirmation's statement/permanence/remedy are journey-pinned BE sentences; the dialog renders them, never paraphrases.
- **Off-cycle idempotency:** the BE's IdempotencyInterceptor replays on the header; minting a UUID per submit makes a double-click a no-op instead of a duplicate.

## Verification

- `bun run test` / typecheck / lint / format / check:styles / check:design-system — all green.
- Browser pass per Tasks (no run/lock mutations on production).

## Plan Change Log

- 2026-11-19 (adversarial plan review, fresh-context reviewer — 15 findings, all verified at source, all folded): **[P1, scope call] off-cycle STAGING WRITES are deferred, not built** — the create/patch DTOs key on `memberships.id` (payroll-offcycle.service.ts:470 `.eq('id', membershipId)`) and no shipped BE surface exposes the membership row id (listCompanyMembers selects user_id only), so the dialogs are unbuildable without a BE change; fenzit-be carries 205 uncommitted files from the owner's concurrent session, so touching it tonight is off the table. The runs tab ships the off-cycle READ (list for the month, staged vs applied) plus a plain note; the write dialogs + ledger entry land when the BE exposes the id. [P1] fixture money numbers re-pinned to what RunSummary actually carries (counts, skip details, warnings, recovery money TEXT, the zero-employee `status:'no_employees'` marker) — the gross/net rows are payslip columns, not summary fields. [P1] `errorResult` extended for every new intent (the old default funnelled failures into a `state-rules-save` error no panel matches). [P2] stale-running re-run affordance (>15 min by startedAt — the 15-min reclaim fires only on re-POST). [P2] `notRunnableReason` is display copy only — the run button is never disabled on it (the BE's real gate is firstPayrollMonth + not-future + cutoff, and a no-join-date company's run legitimately completes with no_employees). [P2] locked-month staged rows render read-only. [P2 decision, resolved] default month = the newest run's month when any exist, else the current month. [P2] new files payrollRunApi/RunAction/RunLoaders to hold the ~300-line rule. [P3] idempotency key minted once per logical submit, POST-only (the interceptor lives only on POST); skip `detail` rendered verbatim (reason → pill label); `status?: 'no_employees'` typed optional; audit truncation note + members fetch to humanize actor/target + label map for all 16 `payroll.*` actions; override pinned as `PUT /payroll/employees/:userId/run-override` with digits-only money text; one GET /payroll/runs serves the history AND the month's run lookup; lock GET 404→null mapped; kit gains explicit runs/lock/offcycle/audit answers (the catch-all `[]` would serve an array as LockView); "Run again" refusals render verbatim on the same paths.

## Review Triage Log

## Implementation Notes

## Code Review

---

## Build record (2026-11-19, overnight run — PARKED GREEN, UNCOMMITTED)

Built to the reviewed plan with all 15 folded findings. Static gates green (typecheck, lint — 2
known react-refresh warns, prettier, css-modules, design-system) and the full suite is
**1044/1044** (14 new tests: runs 11 + audit 3).

Two build bugs the tests caught, both real production defects, both fixed:

1. **The `TABS` set never gained `runs`/`audit`** — the `PayrollTab` type was widened but the
   `Set<PayrollTab>` literal was not, so `readPayrollTab` silently answered `components` for a
   runs URL: every panel branch missed and the main rendered bare. Typechecks green, runtime dead.
   Lesson: a widened union needs its guards widened in the same patch.
2. **The run action read `request.formData()` twice** — the page action parses the body for the
   intent, then delegated to `adminPayrollRunAction(args)` which parsed it again. A Request's form
   body is single-use (Fetch spec), so EVERY run-trigger/lock-month/override-set submit would
   throw `InvalidStateError` in the deployed app. Fix: parse once in the dispatcher, hand the
   `FormData` down.

A third issue was found by probe while debugging the lock test: the kit's fake answers requests
synchronously, so seeding post-lock fixtures after `waitFor(lastSent POST)` races the answer (the
POST had already been served the pre-seed 404). The test now seeds the post-lock world while the
page sits idle and lets a `POST`-keyed fake entry serve the BE's real 200 LockView contract.

Also cleaned: dead `members`/`selfUserId` props on LockCard (and the loader field), dead `month`
prop on RunCard; the kit's month-status knob collapsed to a single `payroll.monthStatus` whose
default is the BE's fresh-company shape (two knobs for one endpoint had begun shadowing the
calendar tests' seeds).

**Handoff:** the 4-lens review round has NOT run — per the standing gate the story is parked
uncommitted in the fenzit-web worktree (15 files, all in the file list above). Next session:
review → triage at source → commit explicit paths → push.
