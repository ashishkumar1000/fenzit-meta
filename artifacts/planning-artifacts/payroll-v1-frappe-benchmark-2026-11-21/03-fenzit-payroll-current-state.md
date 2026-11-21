# Fenzit Payroll — Current State Audit (2026-11-21)

Self-contained factual account of what Fenzit payroll (epic 23) does and does not
have today, across the three repos, as the "current state" half of a competitive
gap analysis. Every claim is verified in code or migrations this session; file:line
or migration filename given throughout. Paths are relative to each repo root:

- **BE** = `/Users/admin/workspace/fenzit-meta/workspace/core/backend/fenzit-be`
- **WEB** = `/Users/admin/workspace/fenzit-meta/workspace/core/frontend/fenzit-web`
- **APP** = `/Users/admin/workspace/fenzit-meta/workspace/core/frontend/fenzit-app`

Legend used throughout: **API-only** = endpoint exists but no console/mobile UI
exercises it; **UI** = has a console or app surface; **pinned** = asserted by tests.

Framing facts (from sprint-status.yaml:497–510 and git):

- Epic 23 ran BE stories 23-1…23-9 + 23-13 between 2026-11-17 and 2026-11-19, then
  web 23-10/23-11 (2026-11-19). Mobile payslip self-service (23-12) is committed in
  fenzit-app (`git log` shows commit 8ec4022 "feat(payslips): 23-12 employee payslip
  self-service") even though sprint-status.yaml:509 still marks it `backlog` — the
  yaml is stale on that line; the code exists and is tested.
- The payroll engine is a **zero-database-functions** design: every read/write is a
  NestJS service table statement with an explicit tenant filter; the only RPC is the
  shared `write_audit_row` (BE src/payroll/payroll.helpers.ts:72).
- The product targets **India SMB payroll for field-technician workforces** whose
  attendance already runs in Fenzit (epics 16–19): LOP is derived from the same
  day-status engine attendance uses; payroll never recomputes attendance
  (BE src/payroll/payroll-run-engine.service.ts:12–14 module comment).

---

## 1. Data model

Every payroll-related table, in migration order. All payroll tables use the house
"deny-by-default" pattern: RLS enabled with **no policies**, all grants revoked from
`public, anon, authenticated`, `select/insert/update/delete` granted to `service_role`
only — the NestJS admin client is the only reader/writer (cited per migration below).
Money on snapshot rows is `numeric(18,2)`; config amounts are exact-decimal **text**.

| Table | Created by | Purpose / key columns | Constraints, FKs, notes |
|---|---|---|---|
| `memberships` | 20261020000001_roles_new_structure.sql:59–79 | One person per company: `user_id`, `tenant_id`, `role` (company_admin\|employee\|viewer), `status` (invited\|active\|removed), `employee_code` (unique per tenant) | One live membership per person (partial unique `memberships_one_live_per_user` where status<>'removed', :83–85); rows never deleted |
| `memberships` payroll columns | 20261117100000_membership_employment_data.sql:27–52 | `join_date`, `exit_date`, `pan` varchar(10), `date_of_birth`, `father_name`, `mother_name`, `spouse_name`, `pf_account_number` varchar(50), `uan_number` varchar(20), `designation`, `department`, `bank_account_number`, `ifsc_code` varchar(11), `bank_name` | CHECKs: exit needs join; `exit_date >= join_date` (:44–48); PAN regex `^[A-Z]{5}[0-9]{4}[A-Z]$`; IFSC regex `^[A-Z]{4}[A-Z0-9]{7}$`. Backfill: join_date = created_at in tenant tz (:83–88); exit_date = latest `member.remove` audit row, clamped to ≥ join (:92–110). `memberships_id_tenant_id_key` unique added 20261117120000:69–70 so every payroll table FKs `(membership_id, tenant_id)` — cross-tenant rows are impossible at the storage layer |
| `audit_log` | 20261020000001:107–159 | Append-only audit: `actor_user_id`, `actor_is_platform_admin`, `tenant_id`, `action` (≤80 chars), `target_user_id`, `details` jsonb | Append-only trigger refuses update/delete/truncate (:135–152); company_admin read policy via `private.current_company_id()/current_member_role()` (:209–214); payroll mutations write `payroll.*` actions here |
| `leave_requests` / `leave_request_days` / `leave_events` | 20260929000001_attendance_leave_tables.sql:36–146 | Leave spans; one row per calendar day incl. off days; event log | State machine trigger (pending→approved/rejected/cancelled; approved→revoked/cancelled, :150–172); partial unique one active leave day per employee/date (:107–109); **`leave_type_id`** added 20261117110000:43–48 with composite FK to leave_types (RESTRICT) |
| `leave_types` | 20261117110000_leave_type_catalog.sql:24–41 then reshaped by 20261119000000 | Name + `paid` boolean (unpaid → LOP). Accrual program adds `code` varchar(20), `accrual_mode` (monthly\|annual\|none), `accrual_days` numeric(5,2), `carry_forward`, `allow_over_balance`, `enabled` (20261119000000:1–29) | Unique (tenant, name); NULL `leave_type_id` on a request reads as paid (never LOP). Fixed four-type catalog per company: earned (monthly, default 1/mo, CF on) / sick (0.5/mo) / bereavement (annual grant) / comp_off (none) — types cannot be created/deleted after the reshape; unmatched legacy rows become disabled remnants |
| `leave_balance_credits` | 20261119000000:241–256 | Manual opening credits/corrections only: `user_id`, `leave_type_id`, `year` int, `days` numeric(6,2) (`<>0`), `source` pinned to 'manual' | Balances are **derived on read** (April–March FY); no scheduler; carry-forward never stored |
| `salary_components` | 20261117120000:33–45 | Component library per company: `name` varchar(60), `is_basic` bool, `active` bool | Unique (tenant, name); **exactly one basic per tenant** via partial unique index `salary_components_tenant_basic_uq … where is_basic` (20261117140000:14–16) — the service probe names the current basic in the 409 and the index is the race backstop |
| `salary_structures` | 20261117120000:47–81 | Per-employee dated revisions: `membership_id`, `effective_from` date, `lines` jsonb (array of `{componentId, amount}` XOR `{componentId, formula AST}`) | Unique (membership_id, effective_from) — a same-date save replaces the row; composite FK `(membership_id, tenant_id) → memberships` cascade; month-start resolution (latest effective_from ≤ month's first day) |
| `payroll_calendar` | 20261117200000:28–44 | Dated policy rows: `divisor_convention` (calendar\|fixed-30\|fixed-26, default fixed-26), `cutoff_day` smallint **1–28** (Feb reason), `pay_date` smallint **1–7** (Code on Wages s.17 reason) | Unique (tenant, effective_from); empty table = defaults fixed-26/25/1 resolved at read time |
| `payroll_state_rules` | 20261117200000:46–50 | One row per company: `notified` bool — whether the company's state has notified its Code on Wages state rules (central Form V template ships either way) | tenant PK; absent row reads false |
| `payroll_deduction_heads` | 20261117220000:6–20 | Named deduction heads: `kind` (flat\|percent), `amount` text (non-empty; money/percent shape enforced in service), `basis` (basic\|gross — percent only), `effective_from`, `active` | Unique (tenant, name, effective_from) — same-name same-date save replaces; name length 1–60 check added 20261117230000:8–10 |
| `payroll_pf_config` | 20261117220000:22–29 (+ id PK 20261117230000:5–6) | Tenant PF-covered switch, dated: `covered` bool | Unique (tenant, effective_from); absent rows = NOT covered |
| `payroll_pf_exclusions` | 20261117220000:31–39 | Per-employee PF exclusion flag (`excluded` bool) | Unique (tenant, membership_id); composite FK cascade; only ever meaningful for never-members (service refuses exclusion when UAN/PF account present) |
| `payroll_runs` | 20261118000000:5–20 | One run: `month` (`^\d{4}-\d{2}$`), `status` queued\|running\|completed\|failed, `initiated_by`, `started_at/finished_at`, `summary` jsonb, `error_message` | Index (tenant, month, status); **partial unique `payroll_runs_one_active_per_month` where status in (queued, running)** (20261118010000:4–6) — the enqueue race backstop |
| `payroll_payslips` | 20261118000000:22–66 (+ 20261118040000:8–10) | The month snapshot + Form V data: `salary_period`, `slip_number`, employee identity block (name, code, father/mother/spouse, designation, department, pan, uan, bank acct/ifsc/bank, date_of_joining), establishment_name (+ `_address`), wage_period_start/end, divisor_convention, cutoff_day, pay_date, `payable_days/lop_days/paid_days/days_worked` numeric(6,2), money columns (`gross_earnings`, `pf_employee`, `pf_employer`, `tds`, `other_deductions`, `total_deductions`, `net_wages`), `earning_lines`/`deduction_lines`/`warnings`/`leave_balances` jsonb | Unique (tenant, salary_period, membership_id) — one slip per employee per month; FKs `(membership_id, tenant_id) → memberships` cascade; run FK cascade |
| `payroll_run_overrides` | 20261118000000:68–79 | Admin-replaced computed amounts: `field` **pf_employee\|tds only**, `amount` ≥ 0, `acknowledged` must be true | Unique (tenant, membership_id, month, field) — survives unlocked re-runs |
| `payroll_recovery_lines` | 20261118000000:81–90 | Over-50%-cap excess raised for later absorption: `month_raised`, `original_amount`, `outstanding_amount` ≥ 0 | Unique (tenant, membership_id, month_raised) added 20261118120000:15–17 (re-run idempotency); composite FK cascade (20261118010000:8–10) |
| `payroll_slip_sequences` | 20261118000000:92–97 | Gap-free slip numbering: PK (tenant, salary_period), `last_seq` | Allocated inside the run write tx via upsert `on conflict … do update set last_seq = last_seq + 1 returning` (engine :266–274) |
| `payroll_month_locks` | 20261118020000:5–12 (hardened 20261118030000) | Permanent month lock: PK (tenant, month), `locked_by`, `locked_at`, `confirmation` jsonb | `month` regex `^\d{4}-(0[1-9]\|1[0-2])$` (2026-13 not a month, hardening :8–12); `locked_by` FK → users restrict; **no unlock concept** |
| `payroll_off_cycle_lines` | 20261118020000:14–30 (hardened 20261118030000:14–44, 20261118120000:12–13) | One-off lines per employee per month: `label` 1–80 (trimmed check), signed `amount` (`<> 0`), `tag` wage\|bonus, `status` staged\|applied, `acknowledged`, `created_by` | Unique (tenant, membership_id, month, label); `created_by` FK → users restrict; month regex 01–12; index (tenant, month, status) |
| `report_queue_pauses` | 20261118040000:15–22 | Per-tenant report-queue pause (`paused`, `paused_until`, `paused_by`) | tenant PK; payslip PDFs (and other reports) fence against it |

RLS note: none of the payroll tables has a single RLS policy — they are invisible to
the public API entirely; every access flows through the service role behind the
NestJS controllers. The two exceptions in the wider stack are `memberships` (RLS on,
no policies, revoke anon/authenticated — 20261020000001:102–103) and `audit_log`
(company_admin read policy, :154–159).

Effective-dating idiom (uniform): every config table is keyed by `effective_from`
and resolved by "latest row with `effective_from ≤ the run month's first day`
(month-start resolution)"; a same-date save replaces the row; a mid-month-dated
change first takes effect on the NEXT month's run; locked months keep run-time
snapshots (BE src/payroll/effective-dating.ts:1–49, resolveEffective :36–49).

---

## 2. Engine contract — the monthly run as implemented

### 2.1 Enqueue (`POST /payroll/runs`) — BE src/payroll/payroll-run.service.ts

1. Month must be a real `YYYY-MM` (:67–69).
2. **First-payroll-month bound**: the earliest `join_date` among active employee
   memberships; a month before it is refused with the plain-English reason
   (:75–81; bound derived in payroll-month-status.service.ts:112–126).
3. **Future month refused** — the run opens only once the month has begun in the
   tenant timezone (:86–90; tenant tz from `tenants.timezone`, :250–258).
4. **Cut-off gate (tenant time)**: within the run month, the run opens on the
   month's resolved cut-off day, never before (:91–101; resolved from
   `payroll_calendar`, :260–281).
5. **Permanent lock gate**: a locked month cannot re-run — 409
   `PAYROLL_MONTH_LOCKED` (:106–111).
6. **Idempotent enqueue**: an existing queued/running run for the month is
   returned as-is; a stale running run (started > 15 min ago) or a never-claimed
   queued run (> 15 min old) is failed so retry can proceed (`STALE_RUNNING_MS`
   :39, reclaim :128–156).
7. Race backstop: a 23505 from the one-active-run partial unique returns the
   winning run instead of failing (:168–182).
8. **Fire-and-forget execution**: `executeRun` runs in-process; the API answers
   202 once the row is queued (:189–195). No external queue/worker.

### 2.2 Execution (`PayrollRunEngineService.executeRun`) — BE src/payroll/payroll-run-engine.service.ts

Claim: `queued → running` guarded update that also captures `initiated_by` as the
audit actor (:203–213). Then `computeMonth` (pure reads, :525–1374), then ONE write
transaction (:234–404) that:

- takes the tenant+month `pg_advisory_xact_lock` (same key family as lock service
  and attendance date gate — `payrollRunAdvisoryKey`, src/common/pg/advisory-keys.ts:19) (:236–238);
- re-checks the run row `for update` still `running` (:239–245);
- **re-probes the month lock inside the tx** — a lock decided while the run was
  queued fails the run with zero payslip changes (:249–258);
- **destroy-and-replace**: deletes the month's payslips then re-inserts them
  (:260–333); slip numbers are allocated gap-free from `payroll_slip_sequences`
  (`PS-YYYY-MM-0001…`) (:266–274);
- flips the **exact captured staged off-cycle ids** `staged → applied` with a
  status re-check (:341–350);
- updates recovery rows' outstanding by row id (:352–359);
- deletes this month's own untouched raised recovery rows and re-raises fresh
  excess (re-run idempotency) (:367–372), merging into partially-absorbed rows on
  conflict (:382–395);
- marks the run completed with the summary jsonb (:397–403).

After commit: superseded payslip PDF objects (report_requests rows keyed by the
destroyed payslip ids) are deleted best-effort (:406–408, :452–481). Audit rows
`payroll.run_completed` / `payroll.run_failed` are written best-effort
(:410–416, :430–437). Failure marks the run failed with a 500-char message and
leaves zero payslip changes (:417–437).

### 2.3 Payable-days derivation — verified in code

- Population: memberships with `role='employee' AND status='active'`, ordered by
  employee_code, **deduped by user_id** (one person, one payslip) (:595–622).
- **Payable window = employment window ∩ the run month itself** — from
  `max(join_date, month-01)` to `min(exit_date, month-end)`
  (src/payroll/run-window.ts:77–92; consumed at engine :830–840).
- **Month-only payable capped keep-first**: the payable window is capped at the
  divisor **keeping the EARLIEST dates** (`window.slice(0, divisor)`) —
  run-window.ts:130–132; the discarded tail loses pay and LOP alike within the
  payable month. Fixture-pinned: Oct 20–31 joiner under fixed-26 → 12 payable
  days (run-window.ts:4–8 header comment). Divisor from the resolved calendar
  row: `calendar` = real month length, `fixed-30` = 30, `fixed-26` = 26
  (engine :561–570).
- Skip reasons (employee appears in the run summary `skips`, no payslip):
  `missing_join_date` (:983–991), `not_configured` (no effective structure,
  :992–999), `empty_window` (:1001–1009), `never_enrolled` (no attendance
  enrolment tracked anywhere in the LOP window — `trackedAny` probe, :1010–1022).
- Scale guard: the whole-population single grid pass refuses above 20,000
  employee-days per run (`population.length * 62 > 20000`) (:872–874).

### 2.4 LOP derivation ("ownership LOP") — verified in code

- The run reads the **shared day-status grid** (`readDayStatusGrid` from
  src/common/day-status/grid-reader.ts — the same engine attendance uses) once
  over the union of all payable+LOP windows (:876–901), plus a single SQL read of
  **approved unpaid-typed leave days** joined to leave_types (`t.paid = false`)
  over the grid span (:904–930). A NULL leave type reads as paid.
- **LOP window = the OWNED date set, never capped**: month M's run owns M's dates
  ≤ cutoff(M) **plus M−1's post-cut-off dates** (prior-period days), always
  intersected with the employment window (run-window.ts:100–126, ownedByRun
  :62–73). The canonical example: November's run LOPs an Oct-27 unpaid leave even
  though Oct-27 is not payable in November (run-window.ts:9–17).
- **One LOP source per date, precedence**: owner correction override >
  approved unpaid leave > day-status `absent`. `checkout_missing` and
  no-attendance-data days inside a partially-tracked window are **paid and
  flagged**, never LOP (src/payroll/run-lop.ts:42–94; precedence at :54–86).
  Half-day = 0.5; the total snaps to one decimal to kill float drift (:92).
- `paid_days = max(0, payableDays − lopDays)` (engine :1051); a negative shortfall
  warns on the payslip ("net is floored at zero and the shortfall needs an
  off-cycle correction") (:1096–1100).
- Form V "days worked" is presentation-only: present=1, half_day=0.5 over the
  kept payable dates; weekly offs/leave contribute 0 and the buckets never sum to
  the month (:1027–1036).

### 2.5 Earnings, rounding, formulas

- Every structure line is evaluated by the shared AST evaluator
  (`evaluateStructure`, src/payroll/formula.ts:150–253): amount lines stand;
  formula lines may chain through other lines. Save-time validation rejects
  cycles (naming the chain), zero-operand division, negatives, depth > 8,
  > 32 nodes, > 100 lines (formula.ts:20–22, structures.service.ts:245–355).
- **Proration**: each line earns `(componentAmount / divisor) × paidDays`; a full
  month with no LOP yields exactly the structure amount under every divisor
  (src/payroll/run-math.ts:15–30).
- **Rounding**: every emitted money figure is rounded ONCE, half-up to paise with
  an epsilon term for true-decimal `.xx5` boundaries
  (src/payroll/formula.ts:265–274); intermediates stay unrounded floats
  (run-math.ts:1–5 header).
- Structure total (unprorated monthly amounts) is the TDS projection base; earned
  basic is the PF base (:1054–1092).

### 2.6 Deductions (in order, each basis clamped at zero)

1. **PF employee**: 12% × min(earned basic, effective-dated ceiling)
   (src/payroll/statutory.ts:56–69). Ceiling rows in code: ₹15,000 from
   2014-09-01, ₹25,000 from 2026-09-17, resolved by month-start
   (statutory.ts:29–49). Coverage decision (`employeePfCovered`):
   an **ever-member** (populated UAN or PF account number) is covered regardless
   of the switch; otherwise switch (month-start resolved, absent = off) AND not
   excluded (pf-config.service.ts:144–151). Wage-tagged off-cycle earnings join
   the PF base; bonus never does (offcycle-math.ts:73–81). **pf_employer is
   recorded, never deducted, and equals the employee figure — v1 has no EPS/EDLI
   split** (statutory.ts:52–55; engine :1254).
2. **TDS** (new-regime estimator, FY 2026-27 constants in code — statutory.ts:71–176):
   slabs 0–4L nil / 4–8L 5% / 8–12L 10% / 12–16L 15% / 16–20L 20% / 20–24L 25% /
   >24L 30%; ₹75,000 standard deduction; resident-only s.157 rebate (income ≤ ₹12L
   pays nothing) with marginal relief above the threshold; 4% cess
   (statutory.ts:85–100, annualTax :132–176). Projection
   (run-math.ts:102–118): annual = current monthly structure × months employed in
   FY (join/exit bounded, future months count) + signed off-cycle amounts, less
   prior-FY TDS already deducted (read from prior payslips of THIS FY, engine
   :753–770), spread over remaining FY months including the run month
   (`fyRemaining`, engine :1376–1381). **FY is hardcoded 2026-04…2027-03**
   (engine :167–168; run-math.ts:127–128) — a new FY needs a code change.
3. **Deduction heads**: company-defined flat or percentage heads; percent computes
   `(amount/100) × earnedBasic | gross` (engine :1143–1155). Month-start resolved
   per name, active-only, fail-closed (deduction-heads.service.ts:276–322).
4. **Recovery lines** (earlier months' cap excess): deducted at outstanding
   amount; **absorbable only by LATER months' runs** (`month_raised < month`
   filter, engine :714–716); reconciled by row id, never positionally
   (:1156–1213).
5. **Off-cycle negatives**: recovery-style deductions with the deliberate
   `offcycle-recovery:` prefix so they are never confused with recovery rows
   (offcycle-math.ts:19, :56–66; engine :1163–1166).
6. Admin **run overrides** (pf_employee | tds) replace the computed amount and
   survive unlocked re-runs (:1116–1117, :1139–1140).

### 2.7 The 50% cap and the leaver's final run

- Normal run: total deductions may not exceed **50% of post-LOP pre-deduction
  gross**; a breach clamps lines **proportionally** (residual pinned on the
  largest line so totals land exactly) and raises the excess as a recovery line
  for the next run (run-math.ts:56–89; warnings at engine :1214–1225).
- **Final run** (`isFinalRun`: the run of the leaver's exit month —
  offcycle-math.ts:110–112): governed lines (PF + heads) clamp at 50% as usual
  (excess REPORTED, never raised — no later run exists); **TDS and every
  recovery-shaped line deduct in full outside the cap**; net floors at zero;
  when the floor bites, recovery rows absorb min(outstanding, headroom) in order
  and the still-outstanding balance is reported for final settlement
  (finalRunCap, offcycle-math.ts:152–217; wiring engine :1124–1190). TDS uses
  `remainingFyMonths = 1` so the leaver's remaining estimate deducts in full
  (:1128–1138).

### 2.8 Lock, month status, calendar

- **Permanent month lock** (payroll-lock.service.ts:64–184): decide+insert as one
  tx holding the month's advisory key exclusively; refuses re-lock (409), a run
  still queued/running (409 `PAYROLL_RUN_IN_PROGRESS` with reclaim remedy), and a
  month with no completed run (409 `PAYROLL_MONTH_NOT_RUN`). The stored
  `confirmation` quotes the permanence copy, the off-cycle remedy, and LISTS the
  month's remaining staged off-cycle lines (:122–150). **There is no unlock.**
- **Month status read** (payroll-month-status.service.ts:42–139): resolved
  calendar (defaults fixed-26/25/1 at :10–14), lock flag, first-payroll-month
  bound + plain-English notRunnableReason. This is the run engine's config read
  too.
- **Calendar** (payroll-calendar.service.ts:71–183): same-date save replaces;
  cut-off 1–28 with the February reason; pay date 1–7 with the CoW s.17 reason;
  identical re-save writes nothing and audits nothing.
- **State rules** (payroll-state-rules.service.ts): one notified boolean; absent
  row reads false; "false" save is a no-op.

### 2.9 Off-cycle lines (CAP-10) — payroll-offcycle.service.ts

- Admin stages a **signed** line for one employee in an unlocked month: positive
  = earning (flat, never prorated; joins gross → 50%-cap basis; wage tag joins
  the PF base, bonus does not); negative = recovery (server-side
  employer-liability acknowledgment enforced — assertAmount :419–434; zero
  refused).
- Month validation: not future, within the first-payroll-month bound, unlocked
  (re-checked inside the advisory-key tx), employee must be an active
  employee-role membership with an effective structure for the month
  (validateTarget :446–517).
- Staged-only edits (PATCH re-targets month/employee/amount/label/tag — the
  orphan remedy; concurrent-retarget 409 `OFFCYCLE_LINE_CHANGED` :233–275) and
  cancel (DELETE, :350–413); applied lines are immutable (422).
- Serialization: create/update/cancel and the lock decision and the run write tx
  all take the same month advisory key — edits wait out an in-flight run
  (:80–88, :233–240; lock.service.ts:77–80; engine :236–238).

### 2.10 Payslips (snapshot + PDF) — payroll-payslips.service.ts

- **Admin list** `GET /payroll/payslips?month=` — any month state (pre-lock
  preview included), slip-number order, each with its live PDF request state
  (:118–136, withPdf :400–432 — one batched request read per list, newest per
  payslipId).
- **Employee history** `GET /payroll/payslips/me` — **LOCKED months only** (inner
  join against payroll_month_locks; pre-lock rows filtered, never leaked),
  newest first (:141–171).
- **Employee single** `GET /payroll/payslips/me/:month` — branched plain-English
  404s: out of runnable bound → "hasn't been run"; not locked → "will appear once
  payroll locks the month"; no row → "no payslip for you in {month}"
  (:272–309).
- **PDF**: both legs queue a `payslip` report request (plain insert into
  `report_requests`, params triple month+membershipId+payslipId — a re-run's new
  payslip never inherits a stale request, :39–43); in-flight dedupe (queued/
  generating returned as-is; failed never blocks a re-request); PT429 SQLSTATE →
  429 with the in-flight cap copy (:317–360). The reports worker renders the
  Form V PDF (pdfmake → R2; BE src/reports/registry/payslip.data.ts:113–126
  tenant-scoped fetch by payslipId with a pre-render supersession verify) and
  GETs presign fresh read URLs on every read, default TTL 600s (:498–530).
  Employees poll via their payslip GET — they hold neither `report.read` nor
  `report.request` (:99–104 comment).

### 2.11 Audit trail — payroll-audit.service.ts

- Read surface over the generic append-only `audit_log`: `payroll.*` actions,
  newest first, id tiebreaker, limit 100 (:31–61). One entry per mutation is
  written best-effort by every payroll service via the shared `writeAuditRow`
  helper through the `write_audit_row` RPC (payroll.helpers.ts:50–89 — an audit
  failure never undoes the change it describes).

---

## 3. Configuration model — what an admin can actually configure end to end

| Config surface | What it is | Where | Effective dating |
|---|---|---|---|
| Component library | Names + the single `is_basic` (PF base / Form V basic line) + active flag; renames reach the next run; deactivation refused while any structure references the component (service lists employees) | BE payroll-components.service.ts (create :107–133, update :179–227; basicExistsError + 23505 race backstop) | n/a (mutable) |
| Salary structures | Per-employee dated revision; lines = amount XOR formula AST per component; basic must be included; validation at save (cycles/zero-div/negatives/depth/nodes/12-digit-2dp amounts) | salary-structures.service.ts:245–355 | Month-start (mid-month date = next month's run); same-date replace |
| Deduction heads | Flat or percent (basis basic/gross) heads; retire with confirm; retired head = fail-closed drop from runs | deduction-heads.service.ts | Month-start; unique (name, effective_from) replace |
| PF switch | Company-level covered on/off | pf-config.service.ts | Month-start; absent = off |
| PF exclusions | Per-employee; never-members only (ever-member refused, pf-exclusion.service.ts:110–118) | pf-exclusion.service.ts | n/a (flag) |
| TDS | Read-only constants view (slabs, std deduction, rebate, cess) — **not configurable** | statutory.controller.ts:124–135, statutory.ts:106–124 | Hardcoded FY 2026-27 |
| Calendar | Divisor convention, cut-off day, pay date | payroll-calendar.service.ts | Month-start; defaults fixed-26/25/1 |
| State rules | Notified flag (copy caveat only) | payroll-state-rules.service.ts | n/a |
| Employment data | join/exit dates, PAN, DOB, family names, PF account/UAN, designation, department, bank account/IFSC/bank on the membership | members.controller.ts:134–164, members/dto/update-employment.dto.ts (PAN/IFSC shape) | n/a |
| Leave types | Fixed four-type catalog; owner edits VALUES only (rate/days, CF, over-balance, paid, enabled); four common types seeded at setup (leave-catalog.seed.ts:14–40) | attendance/leave-types.service.ts | n/a |
| Manual leave credits | Opening credits / offsetting corrections per type-year | leave-balance.service.ts (applyCredit :390+) | n/a |

Formula builder reality check: the BE accepts arbitrary ASTs (binary +−×/, percent-of,
component refs), but the **web editor offers only two shapes** — "X% of a component"
and "X% of a component ± flat" — deeper stored ASTs render as a caption telling the
owner to replace them (WEB src/features/admin/components/payroll/StructureEditor.tsx:14–19).

**What an admin CANNOT configure today**: earning heads outside the per-employee
structure (no global earning components/recurring allowances); any second statutory
(ESI/PT/LWF/gratuity); regime choice (new-regime TDS only); any per-employee
statutory exemption/declaration; PF EPS/EDLI split; any reporting/exports config;
any payslip delivery channel beyond in-app download.

---

## 4. API surface — every payroll controller route

All under `/api/v1`, JWT bearer auth, `@Can(...)` permission. Every route also
validates tenancy server-side.

| Method | Path | Permission | Controller:line | Notes |
|---|---|---|---|---|
| GET | `/payroll/components` | payroll.config | payroll-components.controller.ts:44 | Library list |
| POST | `/payroll/components` | payroll.config | :60 | Create (optional isBasic) |
| PATCH | `/payroll/components/:id` | payroll.config | :89 | Rename / move basic / deactivate |
| GET | `/members/:userId/salary-structures` | payroll.config | salary-structures.controller.ts:43 | Dated revisions |
| PUT | `/members/:userId/salary-structures` | payroll.config | :66 | Save dated revision (validated) |
| GET | `/payroll/deduction-heads` | payroll.config | payroll-heads.controller.ts:42 | Dated revisions |
| POST | `/payroll/deduction-heads` | payroll.config | :55 | Save dated revision |
| PUT | `/payroll/deduction-heads/:headId/deactivate` | payroll.config | :76 | Retire (confirm required) |
| GET | `/payroll/pf-config` | payroll.config | payroll-statutory.controller.ts:48 | Dated switch |
| PUT | `/payroll/pf-config` | payroll.config | :61 | Save dated switch |
| GET | `/payroll/employees/:userId/pf-exclusion` | payroll.config | :78 | Read exclusion |
| PUT | `/payroll/employees/:userId/pf-exclusion` | payroll.config | :98 | Set exclusion |
| GET | `/payroll/tds-config` | payroll.config | :124 | Read-only FY 2026-27 constants |
| GET | `/payroll/calendar` | payroll.config | payroll-config.controller.ts:54 | Dated revisions |
| PUT | `/payroll/calendar` | payroll.config | :70 | Save revision |
| GET | `/payroll/months/:month` | payroll.config | :94 | Month status (resolved policy + lock + bound) |
| POST | `/payroll/months/:month/lock` | payroll.config | :111 | Permanent lock |
| GET | `/payroll/months/:month/lock` | payroll.config | :134 | Lock receipt (404 unlocked) |
| GET | `/payroll/audit` | payroll.config | :149 | payroll.* trail (100) |
| GET | `/payroll/state-rules` | payroll.config | :162 | Notified flag |
| PUT | `/payroll/state-rules` | payroll.config | :175 | Set flag |
| POST | `/payroll/runs` | payroll.config | payroll-run.controller.ts:46 | Enqueue (202, async) |
| GET | `/payroll/runs` | payroll.config | :68 | Recent 50 |
| GET | `/payroll/runs/:runId` | payroll.config | :78 | Poll status + summary |
| PUT | `/payroll/employees/:userId/run-override` | payroll.config | :98 | Override pf_employee/tds |
| GET | `/payroll/payslips?month=` | payroll.config | payroll-payslips.controller.ts:39 | Month roster, any state |
| GET | `/payroll/payslips/me` | **payroll.own** | :56 | Own history, locked months |
| GET | `/payroll/payslips/me/:month` | **payroll.own** | :68 | Own single, branched 404s |
| POST | `/payroll/payslips/me/:month/pdf` | **payroll.own** | :85 | Own PDF request (idempotent, 429-capped) |
| POST | `/payroll/payslips/:membershipId/:month/pdf` | payroll.config | :114 | Admin PDF request |
| POST | `/payroll/off-cycle-lines` | payroll.config | payroll-offcycle.controller.ts:45 | Stage line (idempotent) |
| GET | `/payroll/off-cycle-lines?month=` | payroll.config | :71 | Lines (staged vs applied) |
| PATCH | `/payroll/off-cycle-lines/:id` | payroll.config | :86 | Edit staged line |
| DELETE | `/payroll/off-cycle-lines/:id` | payroll.config | :114 | Cancel staged line |

Adjacent routes payroll consumes/feeds (details §7): employment
GET/PATCH `/members/:userId/employment` (`member.employment`,
members.controller.ts:134–164); leave catalog PATCH `/attendance/leave/types/:id`
and credits POST `/attendance/leave/credits` (`leave.types`),
balances GET `/attendance/leave/:employeeId/balances` (`leave.read_all`),
approve/reject/revoke/apply/on-behalf (`leave.approve`/`leave.create_on_behalf`),
retype PATCH `/attendance/leave/:requestId/type` (`leave.types`),
corrections PUT/DELETE `/attendance/corrections/:employeeId/:workDate`
(`attendance.manage`).

---

## 5. Admin web UX (fenzit-web console)

Entry: `/admin/company/payroll`, seven URL-tabbed panels
(WEB src/pages/AdminPayrollPage.tsx:21–29), owner-only
(`requireConsoleRole(request, ["owner"])`, payrollRunAction.ts:53).
An EmploymentDialog lives on the Employees page via the
`/admin/company/employees/employment` resource route
(EmploymentDialog.tsx:14–15; routes.tsx:251–254).

| Tab | Panel file | What it does | Status |
|---|---|---|---|
| Components | components/payroll/ComponentsPanel.tsx | Create/edit/rename components, basic designation, deactivate | UI |
| Structures | StructuresPanel.tsx + StructureEditor.tsx | Per-employee dated revision editor; formula builder limited to "X% of component" and "±flat" shapes; pinned (inactive) lines shown | UI |
| Deductions | DeductionsPanel.tsx | Head revisions, deactivate | UI |
| Statutory | StatutoryPanel.tsx | PF switch revisions, per-employee exclusion, TDS constants read-only | UI |
| Calendar | CalendarPanel.tsx | Dated revisions + month status + state-rules flag | UI |
| Runs | RunsPanel.tsx | Month card + resolved policy; **Run payroll** button (re-post reachable in-flight as the reclaim); async status with manual Refresh (no polling loop); run summary verbatim from the BE (employees, payslips, skips labelled, warnings, recovery before→after/raised, off-cycle applied/staged); **permanent lock** via confirm dialog quoting the BE copy; **statutory override dialog** behind the employer-liability acknowledgment; off-cycle lines table; run history | UI |
| Audit | AuditPanel.tsx | payroll.* entries humanized with per-service detail keys | UI |

What the web has **NO UI for** (API-only):

- **Admin payslip roster/PDF**: `GET /payroll/payslips?month=` and
  `POST /payroll/payslips/:membershipId/:month/pdf` are not called anywhere in
  fenzit-web (grep: only OffCycleList/RunsPanel reference "payslip", and only for
  summary counts — verified 2026-11-21). The admin cannot view or download a
  payslip from the console.
- **Off-cycle staging writes**: OffCycleList.tsx:5–11 — read-only; POST/PATCH/
  DELETE have no intents because "they need the membership row id, which no
  shipped members surface exposes" (payrollRunApi.ts:6–9, payrollRunAction.ts:11–13,
  payrollRunLoaders.ts:25–29). Off-cycle lines are **API-only to create**.
- **Report-queue pause** (23-8's `report_queue_pauses` + report.queue permission):
  no web UI ("admin-panel pause UI = future FE story", sprint-status.yaml:504).
- **Leave-type value editing** (23-13 accrual values): "web config UI NOT built —
  configure via the 23-2 admin API pre-launch" (sprint-status.yaml:506).

Web tests: 8 page test files, 60 test cases total (runs 16, tabs 10, components 7,
structures 7, calendar 6, deductions 5, statutory 5, audit 4 —
WEB src/pages/AdminPayrollPage.*.test.tsx).

---

## 6. Employee mobile UX (fenzit-app)

Employees get **payslips only** — no payroll configuration surface of any kind in
the app (verified: the only payroll files in fenzit-app are src/features/payslips/*
and src/services/resources/payrollPayslips.ts; all call the `/me` legs of the API
which are `payroll.own`-gated and self-scoped server-side).

| Screen | File | Behaviour |
|---|---|---|
| Payslips list | APP src/features/payslips/PayslipsScreen.tsx | Full-screen route opened from the Profile tab. Renders exactly `GET /payroll/payslips/me` (locked months, newest first). States: Skeleton on first load; EmptyState "No payslips yet" before the first lock; InlineError + Retry on failed first load; **stale-rows-preserved** refresh failure (banner + Retry above kept rows, list never blanks — :84–98); pull-to-refresh. Row tap → detail (month-keyed) |
| List row | PayslipRow.tsx | Month, net pay figure, "26 paid days · 0.5 LOP" line (LOP omitted at zero — payslipModel.ts:109–114), live PDF badge (Ready / Making PDF / PDF failed — payslipModel.ts:44–59) |
| Detail | PayslipDetailScreen.tsx | Fresh GET per focus (presign URLs never cached — :62–69). Hero card (month, slip number, net pay, paid/LOP, wage period); warnings as neutral notices (:125–129); Earnings card (lines + gross); Deductions card (machine `source` tokens labelled via deductionLabel — pf_employee → "PF — employee share", tds → "TDS", head:NAME verbatim, recovery:YYYY-MM → "Recovery (Month)" — payslipModel.ts:66–74; total); leave-balances section as of month end, omitted when the BE array is empty (:155–174); bottom "Download PDF" button following pdf.status through a three-state tap, 5s poll while in flight, hard stop after 12 ticks (~60s) (payslipModel.ts:16–19, usePayslipDetail.ts) |
| PDF open | usePayslipDetail.ts | POST `/payroll/payslips/me/:month/pdf` then polls the GET; "Open PDF" always starts from a fresh GET so an expired ~10-min URL is unreachable (payrollPayslips.ts:23–27 header) |

Formatting is Hermes-safe: no Intl/toLocaleString; rupee grouping lives in
utils/formatRupee; date-string arithmetic only (payslipModel.ts:1–8).

App tests: PayslipsScreen.test.tsx (states/rows), PayslipDetailScreen.test.tsx
(346 lines), payslipModel.test.ts (176), useMyPayslips.test.tsx (304),
usePayslipDetail.test.tsx (408) — all six payroll feature test files present.

---

## 7. Adjacent integrations

### 7.1 Attendance → payroll (the contract)

- Payroll imports only `common/day-status` (grid reader + `computeDayStatus`),
  never attendance internals (payroll.module.ts:29–41 comment; engine :13–14,
  :876–901). One batched grid read per run over the union of windows.
- **payroll-date-gate** (BE src/attendance/payroll-date-gate.ts): once a month is
  locked, its run-OWNED attendance dates are frozen — a date ≤ its own month's
  cutoff is frozen by that month's lock; a post-cut-off date is owned by the
  successor month and stays editable until that month locks (header :1–32,
  frozenFacts :103–166; shared advisory locks taken before reading lock rows so
  the check cannot go stale :147–156). Call sites, verified:
  - corrections put + delete — corrections.service.ts:154, :280;
  - leave apply — leave.service.ts:263; approve/revoke/cancel action dates —
    :452, :548; retype — leave-types.service.ts:342; on-behalf preview —
    leave-read.service.ts:274;
  - check-in leave auto-cancel uses the non-throwing probe (skips the cancel on a
    frozen date rather than failing the check-in) — check-in-out.leave.ts:50;
  - the disable sweep's approved-arm cancels carve around frozen dates —
    leave-transition.ts:201.
- Run ownership arithmetic (which dates a month owns) is **duplicated by design**
  in attendance's gate (default cutoff 25 mirrored locally, payroll-date-gate.ts:22–35)
  rather than imported from payroll — a documented seam, but a drift risk if the
  ownership rule ever changes.

### 7.2 Leave ↔ payroll

- LOP source: approved days of UNPAID-typed leave types (NULL = paid) — the run's
  own SQL (engine :904–930); owner corrections can override the treatment.
- **Fixed four-type accrual program** (23-13): monthly decimal-rate or annual
  fixed-grant types, carry-forward derived on read (no year-end routine),
  April–March FY, manual opening credits table; balances blocked 422 unless
  per-type over-balance allowed (20261119000000:1–29; leave-balance.service.ts).
- **Payslip leave-balance snapshot**: `captureForRun` (leave-balance.service.ts:277–352)
  captures per enabled accrual type the balance as of the pay-period's last day
  into the payslip's `leave_balances` jsonb — the one date-anchored consumed read
  in the system.
- Leave-type approval/typing and the leave balance endpoints are admin-facing
  (§4); the employee mobile leave-balances UI (23-14) is still backlog
  (sprint-status.yaml:510).

### 7.3 Members / employment lifecycle

- Join date drives the payable/LOP windows, the first-payroll-month bound and the
  TDS months-employed-in-FY; exit date drives proration and the final run.
  Future-dated exits are legal (an active membership may carry one — migration
  comment 20261117100000:56–57) and prorate the months they touch.
- Exit handling is **dates-only**: there is no exit interview / clearance /
  FnF settlement workflow, no deactivation-triggered payroll event. Removal
  backfills exit_date once from the member.remove audit (20261117100000:92–110).
- Deduped population (one payslip per person) guards against duplicate
  memberships (engine :613–622).

### 7.4 Notifications

**None payroll-specific.** Verified: src/notifications/ contains no payroll
references (grep 2026-11-21). Run completion, payslip availability, lock events
and recovery raises are silent outside the console. Payslip availability is
discoverable only by the employee opening the app (locked months appear on the
list).

### 7.5 What payroll SHOULD read but doesn't (observed gaps)

- No overtime / shift differential input: the day-status grid has the data
  (worked_on_holiday, half_day_leave) but nothing earns it.
- Leave accrual data feeds the snapshot, but payroll does not consume
  `allow_over_balance` or comp-off states in any pay rule.
- The 50% cap ignores PT/LWF-style "first ₹X must be paid" conventions — one
  flat cap for all deductions except TDS/recoveries.

---

## 8. Permissions & tenancy

Who can do what (BE src/common/permissions/permissions.ts; the file is the only
place the mapping lives, :3–7):

| Role | Payroll permissions |
|---|---|
| company_admin (owner) | `payroll.config` (:106) — every admin route in §4; plus `member.employment` (:103) for the employment data; plus `leave.types`, `leave.approve`, `attendance.manage` for the LOP inputs |
| employee | `payroll.own` (:117) — own payslip history/detail/PDF only |
| viewer | none (:119–125) |
| platform_admin | **NOT** `payroll.config` — payroll.config, member.employment, leave.types and payroll.own deliberately sit outside ADMIN_PERMISSIONS "so a platform admin does not get them" (:99, :46–49 comment); platform staff keep audit.read but no payroll config or payslip access |

Tenant isolation, three layers (all verified):

1. **Every service query filters `tenant_id` explicitly** (grepped throughout
   src/payroll — e.g. engine :601–606, payslips service :127–129, off-cycle
   service :150–152); cross-tenant ids answer zero rows / 404 with non-leaking copy.
2. **RLS deny-by-default on every payroll table** — no policies, grants revoked
   from public/anon/authenticated, service_role only (each migration, §1). The
   public Supabase API cannot see payroll data at all.
3. **Composite FKs** `(membership_id, tenant_id)` on structures, payslips,
   exclusions, recovery and off-cycle lines make cross-tenant employee references
   impossible at the storage layer (20261117120000:69–76, 20261118000000:99–101,
   20261118020000:28–30).

Run/lock serialization is per tenant-month (one advisory key family,
payrollRunAdvisoryKey — engine write tx, lock decide+insert, off-cycle writes,
attendance gate shared).

---

## 9. Test coverage map

### Backend unit specs (BE src/payroll/*.spec.ts, 24 files)

| Spec | Pins |
|---|---|
| run-math.spec.ts (253) | earnings proration, capClamp proportional+drift, TDS projection, months-in-FY |
| offcycle-math.spec.ts (229) | wage-vs-bonus PF join, final-run assignment, absorption, prefix |
| formula.spec.ts (327) | AST shape caps, cycle naming, zero-div, negatives, rounding epsilon |
| statutory.spec.ts (185) | PF 12% × ceiling rows, FY 2026-27 slabs, rebate, marginal relief, cess |
| payroll-run-engine (covered via journey; no unit spec file) | — |
| payroll-lock.service.spec.ts (309) | lock gates, confirmation, races |
| payroll-offcycle.service.spec.ts (592) | staging matrix, acknowledgments, re-target |
| payroll-payslips.service.spec.ts (496) | locked-months-only, branched 404s, pdf states |
| salary-structures.service.spec.ts (668) | validation pipeline, same-date replace |
| payroll-components.service.spec.ts (526) | basic rule + races |
| deduction-heads.service.spec.ts (539) | shapes, resolution, fail-closed |
| payroll-calendar.service.spec.ts (314) | Feb/CoW validations |
| payroll-month-status.service.spec.ts (325) | bound, defaults, lock flag |
| payroll-state-rules.service.spec.ts (216) | no-op saves |
| pf-config.service.spec.ts (273) / pf-exclusion.service.spec.ts (252) | switch resolution, ever-member rule |
| payroll-audit.service.spec.ts (122) | trail read |
| effective-dating.spec.ts (102) | month-start resolver |

### Backend journey e2e

`test/payroll-journey.e2e-spec.ts` — **7,090 lines, 78 test cases** against a real
DB and real routes, seeded from the canonical fixture; every BE story extended it
(sprint-status.yaml:494–505: "EVERY canonical-fixture money row journey-pinned";
PDF legs gated on real R2 creds; 81/81 twice after 23-13).

### Web (60 tests, 8 files) and App (5 test files + model)

See §5/§6 counts. Web tests pin tab routing, config CRUD copy, run summary
rendering, lock dialog, override acknowledgment, audit humanization. App tests pin
list states (skeleton/empty/error/stale), detail rendering, model formatting
(deduction labels, days copy, balances copy), hooks' polling and error paths.

### Pinned vs uncovered behaviours

Pinned: the canonical fixture's money rows (base/clamped/November/divisor table/
ceiling-binding September), the ownership-LOP prior-period case, final-run
assignment, re-run idempotency, staged→applied/orphan bookkeeping, lock matrix,
acknowledgment rules, month validations, locked-month payslip visibility.

Uncovered / weak spots observed:

- No test pins the 20,000-employee-day scale guard behaviour beyond its existence
  (engine :872–874 has no dedicated spec).
- pf_employer equality with pf_employee is asserted only in statutory tests; the
  EPS-split absence is not a fixture row.
- Web has no test that the admin payslip roster is absent (absence rarely tested);
  the deferred off-cycle write UI is unpinned by design.
- No automated test covers `report_queue_pauses` interaction with payslip PDFs
  beyond the reports module's own specs (BE src/reports/report-queue.service.spec.ts).
- Multi-tenant negative probes exist per service (e.g. off-cycle "cross-tenant
  unit test", sprint-status.yaml:505) but no cross-repo E2E tenancy suite.

---

## 10. Standard-payroll checklist (independent, India SMB lens)

Derived from domain knowledge of Indian statutory payroll for small/medium
companies (EPF Act, ESI Act, PT Acts, LWF Acts, Income-tax Act TDS on salaries,
Payment of Wages/Minimum Wages/Code on Wages, Payment of Bonus Act, Payment of
Gratuity Act). Marked against verified evidence above.

### A. Salary structure & components

| Capability | Verdict | Evidence / gap |
|---|---|---|
| Component library with earning/deduction types | PARTIAL | Components are earnings-only (name + basic + active — 20261117120000); no earning/deduction type taxonomy, no component "type" field |
| Configurable formula engine (CTC split, HRA = x% of basic…) | PRESENT | AST evaluator w/ cycle/zero-div/negative guards (formula.ts:150–253); web builder limited to 2 shapes (StructureEditor.tsx:14–19) |
| Exactly-one basic rule (PF base) | PRESENT | Partial unique index 20261117140000:14–16 + service probe |
| Per-employee structures | PRESENT | Dated per-membership rows, save-time validation (structures.service.ts) |
| Effective-dated revisions | PRESENT | Month-start resolution idiom everywhere (effective-dating.ts:36–49) |
| Recurring allowances outside the structure (fixed monthly conveyance etc.) | PARTIAL | Expressible only as structure lines per employee; no company-wide recurring earning templates |
| Increment/promotion workflow (revision history w/ letters) | ABSENT | Revisions are silent saves; no approval or effective-date workflow beyond same-date replace |

### B. Statutory

| Capability | Verdict | Evidence / gap |
|---|---|---|
| PF employee 12% + wage ceiling (dated) | PRESENT | statutory.ts:20–69 (₹15k→₹25k from 2026-09-17, month-start resolved) |
| PF employer split (EPS/EDLI 8.33%/3.67%), PF ECR challan file | ABSENT | "v1: no EPS split" — statutory.ts:52–55; employer recorded = employee figure; no ECR |
| Per-employee PF coverage (ever-member, exclusion) | PRESENT | pf-config.service.ts:144–151, pf-exclusion.service.ts:110–118 |
| UAN/PF account tracking | PARTIAL | Fields stored + printed (memberships, 20261117100000:35–40); no UAN validation, no EPFO linking |
| ESI (3%/0.75%, wage limit ₹21k, contribution period) | ABSENT | No ESI anywhere in BE/DB (grep across src/payroll + migrations) |
| Professional Tax (state slabs, half-yearly cycles) | PARTIAL | No PT model; a flat head can emulate a fixed monthly PT (deduction-heads), but no state slabs, no per-state registration, payroll_state_rules is only a CoW-notified boolean |
| LWF | ABSENT | Same as PT — no model; only flat/percent heads |
| TDS 192B monthly | PARTIAL | New-regime FY 2026-27 estimator with rebate+marginal relief (statutory.ts:132–176); **no old regime, no regime choice, no employee declarations (80C/80D/HRA exemption), no payroll-driven Form 16/24Q, no challan tracking**; FY hardcoded 2026-04…2027-03 (engine:167–168) |
| Gratuity (4.81% accrual, exit payment) | ABSENT | Nothing in engine or DB |
| Bonus Act (8.33%/20%, eligibility) | PARTIAL | Off-cycle bonus lines exist (tag 'bonus') but are arbitrary amounts; no statutory computation or register |
| Minimum/wages compliance checks | ABSENT | No floor checks on computed wages |

### C. Run lifecycle

| Capability | Verdict | Evidence / gap |
|---|---|---|
| Async run w/ status machine (queued→running→completed/failed) | PRESENT | payroll_runs DDL + enqueue/execute contract (§2.1–2.2) |
| Re-run (destroy-and-replace) before lock | PRESENT | Engine tx deletes + re-inserts; recovery idempotency (§2.2) |
| Draft → approve → pay stages | ABSENT | There is no draft/approval stage: enqueue computes AND commits payslips in one step; "approve" == lock |
| Permanent month lock (no unlock) | PRESENT | payroll-lock.service.ts:64–184 |
| Hold / release individual payslips | ABSENT | No per-payslip hold state; skips are the only population control |
| Off-cycle / supplementary run | PARTIAL | Off-cycle lines ride the NEXT monthly run (staged→applied) — there is no standalone off-cycle run that pays outside the cycle |
| FnF (full-and-final) settlement | PARTIAL | The leaver's final run deducts TDS remainder + recoveries in full and reports unabsorbable excess "for final settlement" (offcycle-math.ts:152–217) — but there is no settlement worksheet, notice-pay/leave-encashment computation, or exit payout record |
| Failed-run retry + stale reclaim | PRESENT | run.service.ts:128–156 |
| First-payroll-month bound, cut-off gate | PRESENT | run.service.ts:75–101 |

### D. Payslip

| Capability | Verdict | Evidence / gap |
|---|---|---|
| Statutory wage slip (Form V / CoW rule 52) fields | PRESENT | Snapshot columns 20261118000000:22–66 + 20261118040000; pdfmake template in reports registry |
| PDF generation + storage | PRESENT | report_requests → R2, presigned reads (§2.10) |
| Employee self-service (view + download) | PRESENT | Mobile app §6; locked-months-only visibility |
| Email / WhatsApp / SMS delivery | ABSENT | Notifications module has zero payroll references (§7.4) |
| Multiple templates / branding | PARTIAL | Single central Form V template; brand-kit folder exists in reports/templates but payslip template is one |
| Editable earnings break-up preview before run | ABSENT | Admin sees numbers only after a run (the summary + payslip roster) |

### E. Integration inputs

| Capability | Verdict | Evidence / gap |
|---|---|---|
| Attendance → payable days/LOP | PRESENT | Shared day-status grid + ownership LOP (§2.3–2.4); corrections frozen by lock (§7.1) |
| Leave (types, balances) → LOP | PRESENT | Unpaid-typed approved leaves; NULL=paid; balances snapshot (§7.2) |
| Arrears / backdated corrections | PARTIAL | Prior-period LOP ownership handles backdated leave/attendance for LOP; backdated PAY adjustments are manual off-cycle wage lines |
| One-time bonus/incentive | PARTIAL | Off-cycle lines (wage/bonus tags) — no incentive plans, no Bonus-Act register |
| Salary advances + installment recovery | PARTIAL | No advance request/approval; negative off-cycle lines + recovery rows emulate employer-recorded recovery with the 50% cap |
| Reimbursements / expense claims | ABSENT | Nothing |
| Overtime / shift allowances | ABSENT | Day statuses exist but no OT pay rule |
| Late-coming / early-going deduction rules | ABSENT | Not modeled (attendance has markers; payroll ignores them beyond absent/half) |

### F. Outputs & reporting

| Capability | Verdict | Evidence / gap |
|---|---|---|
| Payroll summary per run | PRESENT | summary jsonb rendered verbatim (RunsPanel) |
| Salary register (month × employee grid export) | ABSENT | No export endpoint |
| Bank advice / bulk transfer file (NEFT/CSV) | ABSENT | Bank details are stored/printed on slips only |
| Accounting export (journal entries) | ABSENT | Nothing |
| PF/ESI/PT/LWF/TDS statutory registers & returns (ECR, Form 24Q, 16) | ABSENT | Nothing |
| Attendance report (non-payroll) exists in reports registry | PRESENT (context) | src/reports/registry/attendance.* — reports infra reusable, payroll has only payslip |
| Admin views/downloads payslips from console | ABSENT (API-only) | GET /payroll/payslips + admin PDF POST unused by fenzit-web (§5) |

### G. Employee self-service

| Capability | Verdict | Evidence / gap |
|---|---|---|
| View payslip history + PDF | PRESENT | §6 |
| Payroll info visibility controls (hide bank/PAN from others) | PRESENT | Snapshot served per-user; employment data "never exposed to other employees" (migration comments; member.employment is admin-only) |
| Declarations (regime choice, 80C/HRA proofs) | ABSENT | Nothing |
| Tax forecast / YTD view | ABSENT | Employee sees only per-month slips |
| Timesheet/attendance → pay dispute flow | PARTIAL | Corrections exist pre-lock (attendance corrections + review state); no employee-facing "my pay looks wrong" flow |

### H. Audit & compliance trail

| Capability | Verdict | Evidence / gap |
|---|---|---|
| Append-only audit of every payroll mutation | PRESENT | audit_log trigger + payroll.* writer + read API (§2.11) |
| Run snapshot immutability after lock | PRESENT | Lock gates re-run/override/attendance edits (§2.8, §7.1) |
| Actor attribution incl. async runs | PRESENT | initiated_by captured as audit actor (engine:203–213) |
| Payslip version history (per re-run) | PARTIAL | Re-runs replace rows and delete superseded PDFs (engine:406–481); no slip-revision ledger — history is "last run wins" until lock |

### I. Edge cases

| Case | Verdict | Evidence |
|---|---|---|
| Mid-month join (prorate) | PRESENT | payableWindow + cap keep-first (§2.3; fixture C) |
| Mid-month exit (prorate + final run) | PRESENT | exit_date windows + finalRunCap (§2.7; fixture C2) |
| Unpaid leave / half-day LOP | PRESENT | run-lop.ts precedence + 0.5 halves |
| Prior-period (post-cutoff) corrections & leave | PRESENT | ownedByRun + payroll-date-gate ownership |
| Missing join date / no structure / never enrolled | PRESENT | Skip reasons with plain-English copy (§2.3) |
| Deduction breach of 50% cap | PRESENT | capClamp + recovery roll-forward (§2.7) |
| Zero-employee month | PRESENT | no_employees completion + orphaned staged lines (engine:772–823) |
| Duplicate person rows | PRESENT | Dedupe by user_id (engine:613–622) |
| February cut-off > 28 | PRESENT (refused) | calendar validation (§2.8) |
| Future-dated exit | PRESENT | Prorates monthly to it (migration comment; monthsEmployedInFy) |
| Backdated JOIN (structure dated before first run) | PRESENT | Month-start resolution picks it up on next run |
| Currency/rounding drift | PRESENT | Single half-up rounding w/ epsilon (formula.ts:265–269) |

### Checklist verdict summary

**PRESENT**: salary structures + formula engine + basic rule; effective-dated
config; PF employee share w/ dated ceiling; PF coverage rules; TDS new-regime
estimator (FY 2026-27); async run + re-run + permanent lock; attendance/leave→LOP
contract incl. prior-period ownership; off-cycle staged lines; recovery roll-
forward with 50% cap; final-run leaver treatment; Form V payslip PDF + R2 +
presigned downloads; employee mobile self-service; append-only audit; tenancy
isolation; skip/warning surfacing.

**PARTIAL**: earning-side component taxonomy; recurring allowances; increments;
PT/LWF (generic heads only); TDS (no regime choice/declarations/Form 16; FY
hardcoded); bonus (arbitrary lines, no Act math); off-cycle (no standalone run);
FnF (no settlement flow); arrears (manual lines); advances (no advance flow);
payslip templates (single); payslip history (no revision ledger); pay dispute
(corrections only, pre-lock).

**ABSENT**: PF employer split + ECR; ESI; PT state slabs; LWF; gratuity; old
regime + declarations + Form 16/24Q; payslip email/WhatsApp; salary register /
bank advice / accounting / statutory exports; admin payslip viewer in console;
off-cycle staging UI; hold/release; draft-approve stage; overtime; expense
claims; notifications around payroll.

---

## Top 10 absences (highest-impact gaps for an India SMB payroll product)

1. **No ESI** — no contribution computation, wage-limit or period logic anywhere.
2. **No Professional Tax / LWF state engine** — only generic flat/percent heads;
   payroll_state_rules is a single CoW-notified boolean, not a state rules engine.
3. **No PF employer split (EPS/EDLI) and no ECR/challan export** — employer share
   is recorded as a mirror of the employee figure (statutory.ts:52–55).
4. **No income-tax declarations or old regime** — TDS is a new-regime-only
   estimator with hardcoded FY 2026-27 constants and no Form 16/24Q output
   (statutory.ts:71–176; engine:167–168).
5. **No gratuity** — not modeled at all.
6. **No reporting/exports** — no salary register, bank advice/transfer file,
   accounting export, or statutory registers (reports registry holds only payslip
   + attendance + job activity).
7. **No payslip delivery** — no email/WhatsApp/SMS; the notifications module has
   zero payroll hooks; employees must open the app to discover a payslip.
8. **No advances / reimbursements / expense claims** — recovery-style negative
   off-cycle lines are the only employer-recorded recovery mechanism.
9. **No overtime, shift allowances, or late-deduction rules** — attendance data
   exists in the shared grid but nothing earns it.
10. **Console gaps on shipped APIs** — admin cannot view/download payslips
    (GET /payroll/payslips unused by web), cannot stage off-cycle lines
    (OffCycleList read-only), cannot edit leave-accrual values or pause the
    report queue; and there is no draft/approve stage or hold/release on the run
    lifecycle (enqueue commits payslips immediately; lock is the only gate).

---

## Appendix A — Spec-vs-code drift notes

- sprint-status.yaml:509 marks 23-12 (mobile payslips) `backlog`, but the feature
  is committed in fenzit-app (8ec4022) with five test files — the yaml line is
  stale relative to code.
- The canonical-fixture "September payable 25" text divergence (fixture gives 26
  under the ownership rule) is documented and adjudicated in run-window.ts:14–17;
  PF row identical either way (ceiling binds).
- The off-cycle staging UI deferral is a deliberate ledgered debt
  (deferred-work.md referenced from sprint-status.yaml:508), not an oversight:
  the API ships while the console waits on a memberships.id surface.

## Appendix B — Sources

- BE: src/payroll/* (all 50 files read), src/attendance/payroll-date-gate.ts,
  leave-balance.service.ts, leave-catalog.seed.ts, corrections/leave services
  (gate call sites), src/members/members.controller.ts, src/common/permissions/
  permissions.ts, src/common/day-status/keys.ts, src/reports/registry/payslip.*,
  supabase/migrations (16 payroll-adjacent files read in full), test/
  payroll-journey.e2e-spec.ts.
- WEB: src/pages/AdminPayrollPage.tsx + 8 test files, src/features/admin/
  payroll{Api,Loaders,Action,RunApi,RunLoaders,RunAction,Views,Format}.ts,
  src/features/admin/components/payroll/* (11 components).
- APP: src/features/payslips/* (6 source + 5 test files),
  src/services/resources/payrollPayslips.ts.
- Artifacts: planning-artifacts/epics-attendance-payroll-qa.md;
  implementation-artifacts/sprint-status.yaml (epic-23 block); plan-23-* file
  inventory; fenzit-app git log (commit 8ec4022).
