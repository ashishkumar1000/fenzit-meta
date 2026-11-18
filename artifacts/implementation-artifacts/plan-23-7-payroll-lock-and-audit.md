# Plan — Story 23-7: Payroll lock + audit trail (BE)

- **Status:** DONE (2026-11-18) — journey 57/57, unit suites green (baseline reds only), review round triaged (log below), committed to fenzit-be. 23-8 NOT started — the owner withheld consent (story 23-8+ needs their go-ahead).
- **Story:** epic-23 id 7 (BE) · CAP-9 + CAP-11

## Intent

A permanent month lock (no unlock in v1): a month that never ran (or whose only runs failed — zero payslips) cannot be locked (409, "run payroll first"); locking freezes re-run, payslip edit and off-cycle targeting (each 409 `PAYROLL_MONTH_LOCKED`) and month M's PRE-cut-off attendance dates only (post-cut-off days stay editable until M+1's run consumes them). Config edits are never blocked (effective-dated rows keep snapshots). The month-status API flips `locked: true`. The audit trail: every payroll change is already in the generic `audit_log` via the shared writeAuditRow helper — this story adds the READ surface. Plus the off-cycle-lines table lands now (deny-by-default RLS) so story 9 builds on it.

## Audit idiom decision (per the story: pick and say why)

**Generic `audit_log`** — every payroll mutation (structures, heads, calendar, runs, locks, state rules, PF config, exclusions, overrides) has written `payroll.*` actions through the shared `writeAuditRow` helper since 23-3; a domain append-only table would duplicate that trail for zero reader benefit. The read endpoint orders by `created_at desc, id desc` (id = the monotonic tiebreaker, uuids sort randomly BUT the house index is (tenant_id, created_at desc) — the tiebreaker is `created_at + id` as the story allows "a monotonic tiebreaker per the chosen idiom"; the index serves it).

## Schema (migration 20261118020000_payroll_lock_and_off_cycle.sql)

- `payroll_month_locks` — tenant_id, month text, locked_by uuid not null, locked_at timestamptz not null default now(), confirmation jsonb not null default '{}', PK (tenant_id, month). RLS deny-by-default + service_role.
- `payroll_off_cycle_lines` — id uuid pk, tenant_id, membership_id (composite FK → memberships cascade), month text, label text not null, amount numeric(18,2) not null (negative = recovery), tag text check (wage|bonus), status text check (staged|applied) default 'staged', acknowledged boolean not null default false, created_by, timestamps, unique (tenant_id, membership_id, month, label). RLS idem.

## Code map

- `src/payroll/payroll-lock.service.ts` (NEW) — `lock(user, month)`: never-ran / failed-only-months → 409 "run payroll first"; already-locked → 409 PAYROLL_MONTH_LOCKED; the confirmation carries permanence copy + the off-cycle remedy + the outstanding staged lines (empty until story 9 — read the table anyway); audits `payroll.month_locked`. `isLocked(tenantId, month)` for the gates.
- `src/payroll/payroll-audit.service.ts` (NEW) — `GET /payroll/audit`: the tenant's `payroll.%` audit rows, ordered created_at desc, limit 100, actor/action/target/details echoed.
- Gates:
  - **Re-run** — PayrollRunService.enqueue refuses a locked month → 409 PAYROLL_MONTH_LOCKED.
  - **Off-cycle targeting** — story 9's surface (the table's rows created in 9 refuse at create time).
  - **Attendance** — `src/attendance/payroll-date-gate.ts` (NEW, attendance-local): `assertPayrollDateEditable(tx, tenantId, workDate)` — reads payroll_month_locks + payroll_calendar inline (plain table reads, no payroll-service import — the seam rule); throws 409 PAYROLL_MONTH_LOCKED when workDate's owning month is locked AND work_date ≤ that month's resolved cutoff. Wired into corrections.service put() + delete() as gate 0.
- `src/payroll/dto/payroll-lock.dto.ts` (NEW) — LockView (month, lockedAt, lockedBy, confirmation), AuditEntryView.
- `src/payroll/payroll-config.controller.ts` — + POST /payroll/months/:month/lock, GET /payroll/months/:month/lock, GET /payroll/audit.
- month-status: locked reads the locks table (true/false).
- ErrorCode + `PAYROLL_MONTH_LOCKED = 'PAYROLL_MONTH_LOCKED'`.

## Journey legs (~5)

1. Lock October (the fixture month with payslips) → 200 + the confirmation copy; month-status locked true.
2. Re-lock → 409; re-run October → 409 PAYROLL_MONTH_LOCKED with zero payslip changes; never-ran (2026-12... future — use a month with no runs: 2026-08? before-bound... use the OTHER tenant's month or 2026-07 → 409 run-payroll-first; the failed-only case needs a failed run — covered by the failed-path leg? That leg's failed run was November — lock November BEFORE its successful retry? Order matters — simplest: a fresh month with only a failed run: corrupt → run → failed → lock → 409 run-payroll-first) — one leg.
3. The attendance boundary: correction PUT on Oct 20 → 409 PAYROLL_MONTH_LOCKED; on Oct 27 → accepted (post-cutoff, editable); November's run consumes the Oct-27 day.
4. The audit trail: GET /payroll/audit returns one entry per scripted edit (the lock, the structure saves, the calendar saves...) ordered newest-first with actor/action.
5. Cross-tenant: the stranger's audit shows zero payroll rows.

## Acceptance

Every 409 carries PAYROLL_MONTH_LOCKED (or the run-first copy); the attendance boundary holds; the audit read matches the writes; suites green (baseline reds only).

## Plan Change Log

- Added two error codes beyond the planned one (house idiom = dedicated code per 409 reason): `PAYROLL_MONTH_NOT_RUN` (lock refused before any completed run) and `PAYROLL_RUN_IN_PROGRESS` (lock refused while queued/running). `PAYROLL_MONTH_LOCKED` stays the one true lock code.

## Review Triage Log

Round: 6 parallel reviewers (BMAD blind-hunter / edge-case / verification-gap / acceptance auditor + ponytail correct+safe / fast+lean+tested) over the 23-7 diff; every finding verified at source before a verdict. Pre-review test fix (journey `day-22` → `day-25`): the test was wrong about the frozen 23-6 fixture — the Oct-1 calendar row is at cutoff 25 (fixture comment at journey line ~2925), so the gate's day-25 answer was CORRECT; the boundary behaviour holds identically.

**Patched (all verified, journey + units re-run green):**

1. Audit read lacked the `id desc` tiebreaker the plan's idiom contracted → secondary `.order('id', {ascending:false})`; spec pins both orders (acceptance auditor).
2. **The two lock races** (3 reviewers independently): (a) lock-vs-run — a run enqueued after lock()'s runs-read could execute against a locked month; (b) lock-vs-correction — a correction could commit between the gate's lock read and the lock's insert. Fix: ONE advisory key family `payroll-run:<tenant>:<month>` (src/common/pg/advisory-keys.ts — common ground, the seam rule bars attendance importing payroll internals). `lock()` now decides inside ONE pg transaction holding the key exclusively; the date gate takes the key SHARED before reading the lock row (holds to COMMIT — no re-read needed); the run engine probes the lock row inside its existing write tx. Engine probe path untestable (unstageable race, 4 plain lines) — noted.
3. Run override on a locked month = silently dead write (confirmation copy promised payslip-edit freeze) → `save()` refuses 409 PAYROLL_MONTH_LOCKED; journey leg added.
4. Run-in-progress copy had no remedy for a dead executor's stale `running` row (lock would wedge) → message names the re-run reclaim.
5. Audit `details` non-object guard (jsonb scalar/array reads as {}).
6. DB hardening (new migration `20261118030000_payroll_lock_hardening.sql`, applied to Supabase + on disk): month checks tightened to `^\d{4}-(0[1-9]|1[0-2])$` on both new tables; `locked_by`/`created_by` FK → users (restrict, house pattern); off_cycle `tenant_id` FK → tenants; `label = btrim(label)` (trim-dodge closed); staged-count index (tenant_id, month, status).
7. DELETE-correction gate had zero coverage (a refactor dropping the delete-side call would pass everything) → two journey cases (frozen PUT-date + owned-by-successor DELETE).
8. Stranger-audit leg strengthened: every foreign payroll row must be the stranger's OWN write (their calendar saves / zero-payslip run) — the whole tenant line, not just month_locked.
9. Month-status lock-read error branch untested → unit case (a 500, never a fake "unlocked").
10. Gate's tx comment claimed a visibility guarantee that didn't exist → rewritten to the real advisory semantics.
11. `effective_from` typed `string | Date` in the gate — the resumed tree never typechecked clean (TS2358).

**Dismissed (verified false at source):**

- audit_log index "unverified" — `audit_log_tenant_created_idx` exists (20261020000001).
- Malformed workDate reaching the gate — `put()` validates the shape (line 150) before the tx.
- cutoff_day 0/>31 — DDL constrains `between 1 and 28`.
- Off-cycle amount sign check — plan specifies negative = recovery (deliberate).
- **Composite FK unsatisfiable / migration never applied** — the fast/lean reviewer probed the WRONG project (yufrzvqpucjrvljmcnls, a stale dev DB; `.env.dev` ≠ `.env`). `memberships_id_tenant_id_key` exists since 20261117120000; the journey's lock legs prove the applied schema. Verified the MCP and the backend pooler see the same DB (pnlvreaijzslfymlnoti) — zero rows there is just the journey's afterAll cleanup purging its throwaway tenant.
- payroll.module.ts churn — the 23-6 wiring that missed 42cb9ae (disclosed; lands in the commit message).
- DEFAULT_CUTOFF_DAY duplication — the attendance/payroll seam rule; documented inline.

**Deferred (owner-ledger policy, 2026-11-18):** ONE item ledgered — leave apply/approve can still mutate a locked month's dates. **FIXED the same day (owner-directed follow-up, fenzit-be `8d95289`)** — see the Follow-up section below. The rest were settled in the moment, NOT ledgered: audit-gap watchdog (best-effort idiom is deliberate), audit pagination (limit 100 fine pre-launch), zero-amount off-cycle validation (owned by story 23-9 — noted on its sprint-status row), freeze inventory — DONE during the owner's follow-up (2026-11-18), not deferred: every dated-attendance writer checked against the gate (corrections, leave apply/approve, checkin auto-cancel, disable sweep, check-in/out, replay, me-attendance, weekly-offs/holidays); no second ungated writer found — the leave paths were the only gap. Then: raw-UUID audit actors (UI story), engine probe untestable (accepted for v1, item 2 above).

## Follow-up: the leave-gate fix (2026-11-18, fenzit-be 8d95289)

The owner called the ledgered item in and shipped it the same day. The range-aware gate now covers every leave write path; one shared resolution body (`frozenFacts`) serves three surfaces: `assertPayrollDateEditable` (corrections, unchanged contract + copy), `assertPayrollDatesEditable` (range — refuses a request WHOLE, naming the earliest frozen date), and the non-throwing `hasFrozenPayrollDate` / `frozenPayrollDates` probes. The key discovery: a frozen TODAY is real — the run opens on the month's cut-off day, so a same-day run+lock freezes the cutoff day itself, which is why cancel/revoke/auto-cancel/disable all needed the backstop.

- **Wired (409)**: apply self + on-behalf (gate before the eligibility facts, after the AD-6 replay and both 404s); approve; revoke; employee-cancel.
- **Deliberately ungated**: reject (pending never fed the run — queue hygiene; the disable sweep's past-pending arm accepted on the same grounds); the disable sweep's APPROVED arm instead CARVES frozen dates out (logged) — the 3-lens review caught this arm as the last miss.
- **Skip-not-fail**: the check-in auto-cancel probes and skips (logged) — it runs inside the check-in transaction and the employee at the gate is operational reality, not a payslip edit.
- **Review round** (3 lenses — blind-hunter / edge-case-hunter / ponytail): 1 real miss patched (the sweep arm above), the check-in spec fixture comment corrected to an honest wiring claim (the successor-owned variant; the own-month-cutoff-day shape is the end-to-end-real one), the locks router made param-aware (a wrong-month gate can no longer pass vacuously), advisory-order pin relaxed to set semantics, probe docstring de-overclaimed. Verified safe: deadlock vectors (shared-only attendance txs vs single-key exclusive takers), error precedence (no 409-masks-404 — D10/replay/type-404 all precede the gate), reject-safety against the run's actual reads.
- **Accepted residuals** (recorded, not ledgered): the skip is log-only observability — the stuck approved leave stays visible in the leave list and the ungated reject remains its remedy; an unpaid-typed + attended frozen day leaves a payslip-LOP mismatch whose only remedy is the off-cycle line (23-9); `PATCH /leave/:id/type` is NOT gated — its supabase write path is non-transactional so an atomic gate needs a restructure; owned by story 23-9, the first recompute surface.
- **FE contract note** (for the lock-UX story): the 409 names ONE date (the earliest frozen) and refuses the whole range — do not design an "all frozen dates" list against it.
- **Verified**: journey 58/58 (new leg: apply-on-frozen 409 + nothing written, approve-on-frozen 409 + no transition, reject-on-frozen 200, future approve 200), attendance suites 726 green, tsc clean, lint clean on own files.

## Implementation Notes

### Built (all unit-verified, 318 payroll+gate+corrections tests green)

- Migration `20261118020000_payroll_lock_and_off_cycle.sql` — applied to Supabase AND on disk (staged). `payroll_month_locks` PK (tenant_id, month) + `payroll_off_cycle_lines` (story 9 builds on it), both RLS deny-by-default + service_role.
- `ErrorCode`: `PAYROLL_MONTH_LOCKED`, `PAYROLL_MONTH_NOT_RUN`, `PAYROLL_RUN_IN_PROGRESS` (tail, doc-commented).
- `payroll-lock.service.ts`: isLocked / lock / get. Check order = already-locked → run-in-progress → completed-run required → insert (23505 race → 409 locked) → audit `payroll.month_locked`. Confirmation jsonb: statement / permanence / remedy / stagedOffCycleLines (counted from payroll_off_cycle_lines).
- `payroll-audit.service.ts`: GET audit = audit_log where tenant + `action like 'payroll.%'`, created_at desc, limit 100; null details → {}.
- `attendance/payroll-date-gate.ts`: `assertPayrollDateEditable(tx, tenantId, workDate)` — freeze a date when the month that OWNS it is locked (own month for dates ≤ resolved cutoff; the SUCCESSOR month for post-cutoff dates, incl. Dec→Jan rollover). Plain table reads, no payroll imports; default cutoff 25 inlined.
- `corrections.service.ts`: gate 0 (before the employee advisory lock) in put() AND remove() — even a removal is an edit of final payslip input. acknowledge() NOT gated (read-shaped).
- month-status: third parallel read → `locked` real; run service enqueue refuses a locked month (409 PAYROLL_MONTH_LOCKED) after the cutoff gate.
- Controller: POST + GET `/payroll/months/:month/lock`, GET `/payroll/audit` (payroll.config) in payroll-config.controller.
- NOTE: `payroll.module.ts` also carries the 23-6 controller/provider wiring that MISSED commit 42cb9ae — fold it into the 23-7 commit and say so in the message.

### Resume point (next agent starts HERE)

1. Journey was 55/57; both failures were the same root cause, ALREADY FIXED but NOT yet re-run: node-pg returns `date` columns as JS Date objects → the gate's `effective_from <= 'YYYY-MM-01'` string compare failed → default cutoff 25 won over the fixture's dated cutoff 22 → Oct-20 leg got "day-25" not "day-22"; the audit leg then failed downstream (leg 3 aborted before November ran+locked). Fix applied: `effective_from::text` cast in the SQL + an `instanceof Date` coercion in cutoffOf; gate spec has a new Date-object case (10/10 green).
2. Re-run: `node --env-file=.env node_modules/.bin/jest --config ./test/jest-e2e.json test/payroll-journey.e2e-spec.ts` (≈85 s; throwaway tenant per run, no cleanup; the "did not exit" warning is pre-existing noise). Expect 57/57.
3. Review round (BMAD code-review + ponytail lenses), triage everything (verify at source before verdict), patch/defer with ledger entries.
4. Commit fenzit-be with EXPLICIT pathspecs: src/common/enums/error-code.enum.ts, src/payroll/{payroll-lock.service.ts,.spec, payroll-audit.service.ts,.spec, dto/payroll-lock.dto.ts, payroll-month-status.service.ts,.spec, payroll-run.service.ts, payroll-config.controller.ts, payroll.module.ts}, src/attendance/{payroll-date-gate.ts,.spec, corrections.service.ts}, supabase/migrations/20261118020000_payroll_lock_and_off_cycle.sql, test/payroll-journey.e2e-spec.ts. Then `bunx tsc --noEmit -p tsconfig.build.json` + full `bun run test src/payroll` as the pre-commit sanity. Do NOT run `bun run lint` repo-wide with --fix; only `bunx eslint --fix` own files. (Known: corrections.service.ts carries 2 PRE-EXISTING no-control-regex lint errors — not ours, leave.)
5. Meta: update this doc's status + Review Triage Log, sprint-status (epic-23 story 7 → done), commit + push both repos.
6. Then story 23-8 (payslip snapshot surfaces + Form V PDF) per stories.yaml.
