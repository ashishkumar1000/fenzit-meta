# 05 — Gap Analysis & Payroll V1 Plan (synthesis)

**Date**: 2026-11-21 (overnight benchmark run)
**Inputs** (read in full, cross-checked against code on both sides):

| Report | What it established |
|---|---|
| [01-frappe-docs-feature-inventory.md](01-frappe-docs-feature-inventory.md) | What Frappe HR *advertises*: 47 verified doc pages, 6-step payroll flow, 60-row verdict table, terminology map |
| [02-frappe-payroll-engine-internals.md](02-frappe-payroll-engine-internals.md) | How Frappe *implements* it: data model, slip pipeline with file:line quotes, Payroll Entry flow, tax engine, 24 gotchas, lean-reimplementation notes |
| [03-fenzit-payroll-current-state.md](03-fenzit-payroll-current-state.md) | What Fenzit *actually has*: 50 BE files + 16 migrations + web/app surfaces read, engine contract with file:line, independent India-SMB checklist, top-10 absences |
| [04-ui-ux-reference.md](04-ui-ux-reference.md) | What Frappe's UI *looks like*: desk + ESS SPA screens, 34 screenshots in `ui-shots/`, 8-row affordance-gap table |

**Every claim below traces to one of those four reports (or to Fenzit source cited in 03). Nothing is assumed.**

---

## 1. Executive verdict

Fenzit's payroll **engine core is sound and in several respects ahead of Frappe** (permanent month lock, append-only audit, ownership-LOP with payroll-date gating, 50% deduction cap with recovery roll-forward, native multi-tenancy). What Fenzit lacks is almost entirely **breadth, not depth**:

1. **Statutory breadth** — PT state engine, PF employer split, ESI, LWF, gratuity, old-regime/declarations. Frappe's core hrms doesn't compute most of these either (they live in the separate `frappe/india-payroll` app), so "Frappe has it" really means "the ecosystem has it" — but customers don't care which repo it lives in.
2. **Outputs & delivery** — no salary register, no bank advice file, no payslip email, no statutory exports. The run computes correctly and then stops; the owner's monthly *operational* loop (register → bank → hand slips to employees) is uncovered.
3. **Console completeness on shipped APIs** — admin payslip viewer, off-cycle staging UI, run preview: the API exists, the web UI doesn't.
4. **One time bomb** — TDS FY 2026-27 constants are hardcoded (`engine:167-168`); April 2027 every slip computes wrong tax unless this is parameterized first.

**Recommended V1** = 9 work items (§6), all inside the existing payroll domain, none requiring a new module. Total effort ≈ 20–28 focused agent-days; this maps naturally to a BMAD epic with 9 stories.

---

## 2. How to read the matrix

Verdict scale:

- **V1** — build now; part of the 9 work items in §6.
- **V1.x** — first post-V1 wave; has a named trigger.
- **LATER** — real need, no launch urgency; revisit after V1.x.
- **NEVER** — deliberately out (with reason).
- **KEEP** — Fenzit already better; do not port Frappe's version (§4).

"V1 must cover only must-haves for the most common use cases" (owner's framing). A feature is V1 iff: (a) a typical Fenzit tenant hits it monthly, (b) its absence produces a wrong number, a legal exposure, or a broken operational loop, and (c) it doesn't open a new product surface (new module ≠ payroll V1).

---

## 3. Consolidated feature matrix

### A. Salary structures & components

| Feature | Frappe (evidence) | Fenzit today (evidence) | Verdict | Why |
|---|---|---|---|---|
| Component library | Salary Component doctype, 24 flags (02 §2.4) | Earning components table (name/basic/active; 20261117120000) + separate deduction heads; no type taxonomy (03 §10.A) | **V1** (WI-B) | PT, register exports, and payslip grouping all need an earning/deduction type on one unified component model. Subset of flags only. |
| Formula/condition engine | Admin-authored Python exprs in `_safe_eval` sandbox (02 §2.3) | AST evaluator w/ cycle/zero-div/negative guards (formula.ts:150–253); web builder limited to 2 shapes (StructureEditor.tsx:14–19) | **KEEP engine, V1 for editor** (WI-E touches it) | Fenzit's compiled AST is safer than Frappe's eval sandbox — do NOT copy `_safe_eval` (02 §7.2). Editor needs a third shape (state-conditional amount) for PT and a formula-variable hint list (04 §screens). |
| Exactly-one basic + PF base | Structure validation rules (02 §2.3) | Partial unique index + service probe (20261117140000) | **KEEP** | Already enforced. |
| Per-employee dated structures | SSA doctype, effective-dated (02 §1.1) | Dated per-membership rows, month-start resolution (structures.service.ts; effective-dating.ts:36–49) | **KEEP** | Equivalent semantics, simpler model. |
| Salary structure *templates* (company-wide) | Salary Structure reusable per company/frequency (02 §1.1) | Absent — structure lines are per-employee | **LATER** | Nice at 150-employee onboarding, but bulk assignment (below) covers the pain. |
| Bulk structure assignment | Bulk SSA wizard by filters (02 §1.5) | Absent | **V1.x** (trigger: first 50+ tenant onboarding) | Agent 1 verdict YES (row 5); synthesis softens to V1.x because onboarding is a one-time event, not a monthly loop. |
| Increment/revision workflow | Arrears doctype diffs past months (02 §1.2) | Silent saves; backdated pay changes are manual off-cycle lines (03 §10.A, §10.E) | **V1.x** (auto-arrears) | Backdated revision → auto-generate diff as staged off-cycle lines. Mechanism only, no dedicated UI (agent 1 row 23 agrees: mechanism V1, UI LATER — synthesis: both V1.x since manual off-cycle lines work today). |
| Recurring company-wide allowances | Structure template rows | Expressible only per-employee (03 §10.A) | **LATER** | Covered by templates when they land. |
| Timesheet-based pay | Hour-rate structures (02 §4.2) | Absent | **NEVER** | Fenzit pays salaried field staff; job costing is a different product. |
| Multicurrency | exchange_rate + base_* columns (02 §2.6) | INR-only | **NEVER** | India-only product. |

### B. Statutory (India)

| Feature | Frappe (evidence) | Fenzit today (evidence) | Verdict | Why |
|---|---|---|---|---|
| PF employee 12% + dated wage ceiling | Core hrms has NO PF math — admin formulas only (02 §5); india-payroll app computes EPF | statutory.ts:20–69, ₹15k→₹25k from 2026-09-17, month-start resolved; per-employee coverage rules (pf-config.service.ts:144–151, pf-exclusion.service.ts:110–118) | **KEEP** | Fenzit is *ahead*: computed, dated, tested — vs Frappe's "write your own formula". |
| PF employer split (EPS 8.33% + EPF remainder on ceiling wage — 3.67% is EPF, not EDLI) + employer recording | india-payroll app (02 §5) | ABSENT — employer recorded = mirror of employee figure, which is *wrong data* (statutory.ts:52–55, 03 §10.B) | **V1** (WI-D) | The stored employer figure is factually incorrect today; correction is small math on an existing base. |
| PF ECR / challan export | india-payroll app "Download ECR Text File" (04 §screens) | ABSENT | **V1.x** (trigger: first tenant with 10+ PF members asks for filing) | Depends on WI-D's employer split. |
| Professional Tax state engine | Month-conditional formulas in docs; state engine in india-payroll (01 §2b, 04 §screens) | ABSENT — flat deduction head can emulate fixed monthly PT; no slabs, no half-yearly cycles; `payroll_state_rules` is one CoW-notified boolean (03 §10.B) | **V1** (WI-C) | Highest-frequency small deduction in India; every tenant needs it on day 1. |
| LWF state rules | india-payroll (14 states, varied frequency) | ABSENT | **V1.x** (trigger: second tenant state needing it) | Same shape as PT; do on demand. |
| ESI (3%/0.75%, ₹21k gross ceiling, contribution periods Apr–Oct/Nov–Mar) | india-payroll | ABSENT — nothing anywhere (03 §10.B) | **V1.x** (trigger: any employee with gross ≤ ₹21k) | Agent 1 row 14: "early V1.x, not launch". Contribution-period math is the complex part. |
| TDS 192B, new regime | Slab walk + annual projection + spread (02 §2.5) | New-regime FY 2026-27 estimator w/ rebate + marginal relief (constants statutory.ts:85–100, applied in `annualTax` :132–176); **FY hardcoded 2026-04…2027-03 (engine:167-168)** | **V1** (WI-A) | The estimator's math is fine; the hardcoded FY is a time bomb that breaks every slip from 2027-04-01. |
| TDS: old regime + regime choice | Regime selector (india-payroll; 04 §screens) | ABSENT | **V1.x** (trigger: an employee demands old regime; needs declarations first) | New regime is the statutory default since FY 2023-24; defensible through launch. |
| Declarations (80C/80D/HRA) + proofs + year-end true-up | Declaration/Proof doctypes + forced-proof at last cycle (02 §1.3, 02 §8.G17) | ABSENT | **LATER** | Big UX investment (categories, caps, proofs); agent 1 row 16 agrees. Blocks old-regime properly. |
| HRA exemption min-of-three | regional/india/utils.py:126-142 (02 §5) | ABSENT | **LATER** | Only meaningful with declarations. |
| Surcharge + marginal relief | India regional override (02 §2.5 step 5) | Rebate + marginal relief present; surcharge absent | **LATER** | Affects a tiny minority at 150 users. |
| Form 16 / 24Q e-filing | india-payroll via Sandbox API (01 row 20) | ABSENT | **NEVER** (V1) / LATER via CA workflow | Owner files via CA; heavy integration, no payslip-line impact. |
| Gratuity (rules, 4.81% accrual, exit pay) | Gratuity + Gratuity Rule doctypes (02 §4.8) | ABSENT (03 top-10 #5) | **V1.x** (trigger: first 5-year tenure exits) | Exits are rare pre-launch; Frappe's rule model is simple to port when needed. |
| Bonus Act register (8.33%/20%) | No dedicated Frappe support beyond manual components | Off-cycle bonus lines are arbitrary amounts, no Act math (03 §10.B) | **LATER** | Register + eligibility math on demand. |
| Minimum-wage floor checks | Absent in Frappe core too | ABSENT | **NEVER** | Neither product does it; not a differentiator for V1. |
| Flexible benefits pool (claims, ledger, 3 payout methods) | Benefit Application/Claim/Ledger (02 §2.4) | ABSENT | **NEVER** | Agent 1 row 26 NO; 02 §7.2 explicitly lists as over-engineered for Fenzit scale. |
| Statutory registers hub (EPF/ESIC/PT/LWF pages w/ exports) | india-payroll module pages (04 §screens) | ABSENT | **LATER** | The UI shell for the exports; builds on ECR (V1.x). |

### C. Run lifecycle & operations

| Feature | Frappe (evidence) | Fenzit today (evidence) | Verdict | Why |
|---|---|---|---|---|
| Async run + status machine | Payroll Entry queued >30 employees (02 §3.3) | payroll_runs DDL, enqueue/execute, failed-run retry + stale reclaim (run.service.ts:128–156) | **KEEP** | Parity or better. |
| Duplicate-slip protection | unique(employee,start,end) + pre-submit validation (02 §3.2) | destroy-and-replace pre-lock; permanent lock after | **KEEP** | Different but stricter model. |
| Attendance completeness gate | `validate_attendance` blocks submit on unmarked days (02 §3.2; gotcha 02 §8.3) | Unmarked-day handling not surfaced as a run gate (03 §2.4) | **V1** (WI-E) | The gate catches data-quality problems *before* money is committed. Note Frappe's gate bug (ignores `consider_unmarked_attendance_as`, counts holidays full-weight — 02 §8.3): copy the intent, not the bug. |
| Explicit unmarked-day semantics | `consider_unmarked_attendance_as` setting, default Present (02 §2.2, :626) | Verify in run-lop.ts; if unmarked days are silently paid, make it explicit + configurable | **V1** (WI-E) | Agent 1 row 7 calls this "a subtle but critical default". Field-service reality: missed punches are constant. |
| **Pre-run preview (dry run)** | Two-step Payroll Entry: Get Employees → Create Slips (draft, reviewable) → Submit (02 §3) | Enqueue computes AND commits in one step; owner sees numbers only after commit (03 §10.C, §10.D) | **V1** (WI-E) | Highest-leverage safety item: the owner can verify a 150-employee run before it exists. Frappe's whole desk flow is built around review-before-submit. |
| Draft → approve stage (separate states) | Payroll Entry draft doc + docstatus | Absent; "approve" == lock | **LATER** | Single-operator admin today; preview covers the safety need without a state machine. |
| Hold/release individual payslips | Salary Withholding cycles (02 §1.2) | Absent; skips are the only population control | **LATER** | Frappe's own docs scope withholding to exit scenarios; Fenzit skips cover the common cases. |
| Permanent month lock (no unlock) | Cancel deletes slips + JEs — history is mutable (02 §3.4d) | payroll-lock.service.ts:64–184 | **KEEP** | Fenzit is deliberately stricter; audit-friendly. |
| Off-cycle / supplementary inputs | Additional Salary — one channel, one-off + recurring + overwrite (02 §4.3) | Off-cycle staged→applied lines ride the NEXT monthly run (03 §2.9) | **KEEP model, V1 for UI** (WI-I) | Same semantics; the console can't write lines yet (API shipped, OffCycleList read-only — ledgered debt per 03 App.A). |
| Standalone off-cycle run (pay between cycles) | Payroll Entry with arbitrary date range | Absent | **LATER** | Rare at SMB scale; staged-lines-next-run is acceptable. |
| LWP reversal / payroll correction tool | Payroll Correction doctype (02 §1.2) | Absent (corrections pre-lock only) | **V1.x** (trigger: first owner request to fix a locked month) | Locked months make this a *policy* question first (Fenzit forbids unlock). |
| FnF settlement worksheet | Full & Final Statement netting (02 §4.7) | Leaver final-run deducts remainder + reports unabsorbable excess (offcycle-math.ts:152–217) but no worksheet | **V1.x** (trigger: attrition begins) | Agent 1 row 43 agrees. |
| Serialised runs per tenant-month | No serialization in Frappe (relies on unique checks) | Advisory-lock per tenant-month | **KEEP** | |

### D. Payslip & delivery

| Feature | Frappe (evidence) | Fenzit today (evidence) | Verdict | Why |
|---|---|---|---|---|
| Statutory Form V payslip fields | Salary Slip doctype (02 App.B) | Form V snapshot columns + pdfmake template (20261118000000) | **KEEP** | |
| PDF + storage + presigned download | frappe attach_print | report_requests → R2 presigned (03 §2.10) | **KEEP** | |
| Component-wise YTD/MTD on slip | compute_year_to_date etc. (02 §2.1 step 10) | Per-month slips only; no YTD anywhere | **V1** (WI-F includes YTD columns in register; slip-level YTD V1.x) | Agent 1 row 8: reduces owner queries; cheap once lines are stable. |
| Income-tax breakup fields on slip | annual_taxable/exemptions/till-date/future/current (02 §2.5 step 8) | Absent | **V1.x** (employee-facing) / **V1** (admin preview in WI-E) | Builds on WI-A's parameterized tax. |
| **Payslip email delivery** | email_salary_slip + template + bulk (02 §3.5) | ABSENT — notifications module has zero payroll hooks (03 §10.D) | **V1** (WI-G) | Office staff without the app must learn a payslip exists. Cheap; notifications infra exists. |
| Encrypted payslip PDFs + password policy | generate_password_for_pdf (02 §3.5) | Absent | **LATER** | Agent 1 row 10: nice privacy touch, rarely needed at SMB. |
| Payslip email dedup guard | `via_payroll_entry` flag (02 §8.12) | n/a yet | **V1** (part of WI-G) | Copy the *pattern*: send at exactly one layer (lock time), or you get double emails. |
| Multiple templates / branding | Letter head + template | Single Form V template | **LATER** | One template is fine at 150 users. |
| Revision history per re-run | Frappe keeps cancelled slips | Re-runs replace rows + delete superseded PDFs; "last run wins" (engine:406–481) | **LATER** | Acceptable until an audit asks "what did the October slip say before correction?" |

### E. Off-cycle inputs & adjustments

| Feature | Frappe (evidence) | Fenzit today (evidence) | Verdict | Why |
|---|---|---|---|---|
| One-off bonus/incentive lines | Additional Salary one-off (02 §4.3) | Off-cycle lines w/ wage/bonus tags (03 §2.9) | **KEEP** | |
| Recurring additional amounts (N months) | `is_recurring` window (02 §4.3) | Absent | **V1.x** (trigger: first recurring-recovery request) | Small addition to offcycle staging: `to_date` + monthly repetition. |
| Overwrite structure amount | AS overwrite flag, never re-prorated (02 §4.3, §8.6) | Absent | **LATER** | Useful for arrears; V1.x with auto-arrears. |
| Advance disbursement + installment recovery via salary | Advance doctype + AS recovery + advance-account JE redirect (02 §4.4) | Negative off-cycle lines + recovery rows w/ 50% cap (03 §10.E) — **no advance request/approval flow** | **V1.x** (advance flow) | Fenzit already *recovers* better than Frappe (cap + roll-forward vs Frappe's none); missing the front-door request/approval. |
| Expense claims / reimbursements | Claim → Payment Entry; **never via salary** (02 §4.5; agent 1 row 27) | ABSENT entirely | **V1.x as separate epic** | Agent 1 verdict YES-for-V1; synthesis demotes: zero payslip-line impact, it's an independent module — sequence as its own epic right after payroll V1. Keep Frappe's rule: pay outside salary (tax cleanliness). |
| Overtime pay from attendance | Overtime Slip → AS (02 §4.9) | Day statuses exist; nothing earns them (03 top-10 #9) | **V1.x** (trigger: first OT-heavy tenant) | Agent 1 row 40: "strong candidate for first post-V1". |
| Late-coming/early-going deduction rules | Absent in Frappe core | Absent | **NEVER** | Neither product; skip. |
| Leave encashment | Leave Encashment → AS (02 §4.6) | Absent | **LATER** | Year-end event, not monthly loop. |
| Employee Other Income (external taxable) | Breakup-only doctype (02 §1.2) | Absent | **NEVER** | Edge case; skip. |

### F. Outputs & reporting

| Feature | Frappe (evidence) | Fenzit today (evidence) | Verdict | Why |
|---|---|---|---|---|
| Payroll summary per run | Payroll Entry totals | summary jsonb rendered in RunsPanel | **KEEP** | |
| **Salary register** (month × employee component grid) | `salary_register` report (02 §5) | ABSENT — no export endpoint (03 §10.F) | **V1** (WI-F) | The owner's monthly audit sheet; agent 1 row 50 YES. Trivially derivable from run lines + reports infra is reusable (attendance report proves the pattern). |
| **Bank advice / transfer list** | `bank_remittance` report (02 §5) | ABSENT — bank details printed on slips only | **V1** (WI-F) | Paying 150 people needs a bank-ready list; agent 1 row 51 YES. CSV/NEFT-style layout. |
| Accounting export (journal-ready summary) | 3 JE types w/ cost centers (02 §3.4) | ABSENT | **V1.x** (simple 2-line-per-component export, NOT JEs) | 02 §7.2: for a SaaS without GL, emit register + per-employee net; integrate via export. Do not port JE machinery. |
| Statutory exports (ECR, ESIC, PT/LWF registers) | india-payroll (04 §screens) | ABSENT | **V1.x** ECR, rest LATER | Tied to PF split + statutory hub. |
| Income-tax computation/deductions reports | hrms/payroll/report/* (02 §5) | Absent | **LATER** | Year-end; per-slip breakup covers V1. |
| Monthly attendance sheet export | Documented report (01 row 53) | Attendance page exists (redesigned 2026-11-20) + report infra | **V1.x** | Owner closes attendance before payroll; cheap CSV from existing grid. |
| **Admin payslip viewer in console** | Desk payslip list | API shipped (GET /payroll/payslips + admin PDF POST) **unused by web** (03 §10.F) | **V1** (WI-H) | Pure UI work on a shipped API — cheapest win in the plan. |
| Report queue pause UI | n/a | report_requests pause has no UI (03 §5) | **V1.x** | Ops nicety. |

### G. Employee self-service & mobile

| Feature | Frappe (evidence) | Fenzit today (evidence) | Verdict | Why |
|---|---|---|---|---|
| Payslip history + PDF in mobile | ESS SPA salary_slip views (02 §1 frontend note) | Shipped (03 §6; mobile 23-12/23-14 released) | **KEEP** | |
| YTD hero + FY selector on payslips home | Dashboard.vue YTD card (04 §mobile) | Absent | **V1.x** | Needs slip-level YTD (D above); pattern-level transfer from Frappe's ESS. |
| Tax forecast / YTD view for employee | Income Tax Breakup tab (04 §screens) | Absent | **LATER** | With declarations. |
| Declarations self-service | Declaration/Proof doctypes | Absent | **LATER** | With regime support. |
| Bank-details change request w/ proof | v16.60 ESS flow (01 row 47) | Absent (console edits) | **LATER** | |
| Pay-dispute flow ("my pay looks wrong") | Absent in Frappe | Corrections pre-lock only | **LATER** | |
| Native mobile vs PWA | Frappe ESS is a PWA served from the site (04 §model) | Native RN app | **KEEP** | Architecturally stronger; transfer UX patterns only. |

### H. Audit & compliance

| Feature | Frappe (evidence) | Fenzit today (evidence) | Verdict | Why |
|---|---|---|---|---|
| Append-only audit of payroll mutations | Versioning only, no payroll audit trail | audit_log trigger + payroll.* writer + read API | **KEEP** | |
| Snapshot immutability post-lock | Mutable via cancel | Lock gates re-run/override/attendance edits | **KEEP** | |
| Actor attribution incl. async | — | initiated_by as audit actor (engine:203–213) | **KEEP** | |
| Payslip revision ledger | Cancelled slips retained | Re-runs replace; no ledger | **LATER** | See D. |

### Matrix count: **V1 = 9 work items** (§6) · **V1.x = 12** · **LATER = 18** · **NEVER = 7** · **KEEP (already at parity or better) = 17**

---

## 4. Where Fenzit is already better — do not regress

These are verdicts to *protect* during V1. If an implementing agent finds Frappe doing X and Fenzit doing Y, Y wins unless §6 says otherwise.

1. **Permanent lock vs Frappe's cancel-and-delete.** Frappe's Payroll Entry cancellation deletes all slips and cancels JEs (02 §3.4d) — history is editable. Fenzit's lock is one-way. V1 must not add an unlock.
2. **Append-only audit** (audit_log trigger) vs Frappe's doc versioning.
3. **Ownership LOP + payroll-date gate.** Frappe recomputes LWP from live leave/attendance at slip time and guards with a submit-time check ("cannot apply leave for a salary-processed period", agent 1 row 35). Fenzit's model assigns prior-period corrections to the *owning* run — strictly more correct for backdated edits.
4. **50% deduction cap + recovery roll-forward.** Frappe just throws on negative net and *silently skips the slip in bulk runs* (02 §8.13 — "Run reports success while one employee silently got no payslip"). Fenzit clamps proportionally and rolls the excess forward. Keep.
5. **Computed PF with dated ceiling** vs Frappe core's "no PF math, write a formula".
6. **Advisory-lock serialization per tenant-month** vs Frappe's none.
7. **Idempotency-keyed writes** (X-Idempotency-Key convention) vs Frappe's docstatus checks.
8. **Native multi-tenancy** (composite FKs + RLS) vs one-company-per-site.
9. **Skip reasons surfaced in plain English** — do NOT copy Frappe's silent-skip failure mode (02 §8.13).
10. **Per-run transactional destroy-and-replace** — but borrow Frappe's per-employee fault isolation (WI-E, below).

---

## 5. Frappe logic to borrow (implementation guidance)

Full mechanics live in [02](02-frappe-payroll-engine-internals.md); this is the distilled set for the V1 implementer, mapped to Fenzit.

| # | Borrow | Frappe reference | Fenzit application |
|---|---|---|---|
| 1 | **Two-number discipline** per line: `default_amount` (full-cycle) vs `amount` (prorated) | 02 §2.1, §7.1.1 | When adding YTD/breakup: persist both on payslip lines. Makes future-month tax projection and register totals trivial. |
| 2 | **Single proration point + dependent inheritance**: prorate once on `payment_days/total_working_days`; dependent formula lines read the already-prorated variable, never re-prorate | 02 §2.2–2.3; guard at salary_structure.py:130-149; test test_salary_slip.py:808 | Verify Fenzit's AST engine inherits prorated bases for dependent lines (formula.ts). If any line re-prorates a prorated input, fix — double-proration is the classic payroll bug. |
| 3 | **Tax = annual projection spread per period**: (previous actual + current-for-payment-days + future full-cycle projection − exemptions) → slab walk → (annual − paid-so-far) ÷ remaining periods | 02 §2.5 step 6 (calculate_variable_tax), get_period_factor payroll_period.py:115-153 | Fenzit's estimator already does rebate+marginal relief; verify the spread subtracts tax already deducted in prior months (self-correction property, test test_salary_slip.py:1483). If it recomputes independently per month, mid-year events (raise, LOP month, bonus) will drift. |
| 4 | **Mid-year joiner openings**: `taxable_earnings_till_date` / `tax_deducted_till_date` on the assignment | 02 §7.1.5; SSA warning salary_structure_assignment.py:222-238 | Fenzit onboarded tenants mid-FY need these two nullable columns on the structure/membership config; feeds WI-A. |
| 5 | **One off-cycle channel with source traceability**: source_type/source_id on every injected line | 02 §7.1.7 | Fenzit's off-cycle lines have tags; add source_type/source_id so future features (advances, OT, arrears) plug in without schema churn. |
| 6 | **Per-employee fault isolation in bulk submit** | 02 §3.3 (per-slip savepoint; failed run keeps status + error_message) | Fenzit runs are whole-run transactions. Adopt savepoint-per-employee so one bad member fails alone, with the failure captured in run status — while keeping Fenzit's *surfaced* skip reasons (not Frappe's silent skips). |
| 7 | **Attendance gate intent** (block run on unmarked days) without Frappe's bug | 02 §3.2 + gotcha 02 §8.3 | Gate must respect the unmarked-as-Present default and half-day-holiday fractions. |
| 8 | **Email-at-exactly-one-layer** | 02 §8.12 (`via_payroll_entry` flag) | Send payslip emails once, at lock (or run completion), never per-slip AND per-run. |
| 9 | **Tax row computed last** — after all exempted deductions exist | 02 §8.8 | Confirm Fenzit's deduction ordering keeps TDS last (03 §2.6 lists order; TDS is in it — verify against exemptions if any are added). |
| 10 | **Slab-table authoring rule: inclusive endpoints** (`to = next_from − 1`) | 02 §8.1 | If/when slabs become configurable (WI-A), validate no overlapping/boundary-double-count; test with FY 2026-27 table. |
| 11 | **Rounding remainder on the last line** when splitting a total across rows | 02 §8.15 | Bank advice / register totals: compute per-employee rounded net from unrounded lines so the column sum equals the run total. |

**And the "don't copy" list** (02 §7.2, condensed): `_safe_eval` sandbox → keep Fenzit's compiled AST; Journal-Entry machinery → exports only; multi-currency → INR; frequency matrix → monthly; flexible-benefit engine → never; withholding cycles → hold/release-lite later; lending-app loans → n/a; Payroll Correction + Arrear parallel doctypes → one concept (auto-arrears via off-cycle lines); Redis caching layers → Postgres is fine at this scale.

---

## 6. V1 scope — the 9 work items

Sequencing respects dependencies: **WI-A and WI-B first** (foundation), then statutory, then run safety, then outputs/delivery. Web-only items (WI-H, WI-I) parallelize anytime.

### WI-A — Parameterize the TDS tax year (do first; removes the time bomb)
- **What**: Move FY 2026-27 constants (slabs statutory.ts:85–93, standard deduction :96, rebate threshold :99, cess :100 — applied in `annualTax` :132–176; no surcharge exists in code) out of code (engine FY hardcode at :167–168) *(corrected 2026-11-21 post-review)* into a `payroll_tax_years` table keyed `(tenant_id, fy_start, fy_end)`; month resolution picks the row covering the run month; refuse to run months without a matching row (fail loudly, never silently extrapolate).
- **Frappe reference**: Income Tax Slab doctype w/ `effective_from` + per-slab conditions (02 §1.1); slab-currency validation (02 §2.5 step 2).
- **Acceptance criteria**: (1) FY 2026-27 seeded rows reproduce today's numbers bit-for-bit on the canonical fixture; (2) a synthetic FY 2027-28 row is picked up for April 2027 months; (3) run without a tax-year row → run status failed with a plain-English reason; (4) openings columns (borrow #4) accepted on config and subtracted.
- **Tests**: pin against 02 §7.6 anchors (6) tax self-correction and (7) recurring additions; (5) keeps holding; add a 2027-04 boundary test. *(corrected 2026-11-21 post-review)*
- **Size**: S–M (1–2 days). **Risk**: none — pure refactor + config.

### WI-B — Component type taxonomy (foundation for C and F)
- **What**: One unified `payroll_components` view of earning components + deduction heads with a `type` enum (`earning | deduction | employer_contribution`), a statutory tag (`pf | pt | tds | esi | lwf | null`), and a `prorates_with_payable_days` boolean. Migrate existing tables; keep the exactly-one-basic rule.
- **Frappe reference**: Salary Component `type` + flag subset (02 §2.4); SALARY_COMPONENT_FLAGS persistence set (02 App.C).
- **Acceptance criteria**: (1) all existing runs re-render identically post-migration; (2) register (WI-F) can group by type; (3) PT (WI-C) and PF-split (WI-D) tag onto components without new tables.
- **Flags to adopt now**: `type`, statutory tag, `prorates_with_payable_days`, `exempted_from_income_tax` (wired now: excluded from taxable base, deducted before TDS). *(corrected 2026-11-21 post-review)* Skip: statistical, flexible-benefit, accrual flags (02 §7.2).
- **Size**: M (2–3 days).

### WI-C — Professional Tax state engine
- **What**: `payroll_pt_state_rules` table: `(state, fy_or_effective_from, monthly_slabs jsonb, half_yearly_amount, february_amount, max_monthly_cap)`; month-start resolution like PF ceiling; auto-select employee's PT state from office state (fallback: explicit per-employee override); deduction tagged `pt`.
- **Frappe reference**: month-conditional formula idiom `300 if getdate(start_date).month in (6, 12)` from docs/india-payroll (04 §screens); but build a *rules table*, not admin-authored formulas (Fenzit's ledgered design).
- **Acceptance criteria**: (1) Maharashtra ₹200/month with **February ₹300** (replacement, not a doubling — ₹2,500 is the statutory ANNUAL cap under Art. 276(2); max monthly ₹300); (2) Karnataka >₹25k-gross-only rule testable; (3) employee without state rule → skip reason "PT not configured for state X"; (4) half-yearly states (Kerala; Madhya Pradesh is the gross-minus-PF basis case) supported via `half_yearly_amount` months config. *(corrected 2026-11-21 post-review)*
- **Tests**: table-driven per-state cases; boundary at gross threshold.
- **Size**: M (3–5 days incl. seeding 5–8 common states).

### WI-D — PF employer split + correct employer recording
- **What**: Compute EPS (8.33% of min(earned basic, ceiling)) and EPF-remainder (employee 12% − EPS) per member per run; store three columns (employee / EPS / EPF-remainder) on run lines; **employer PF contribution = EPS + remainder (= the employee figure, 12%)** — the three-column sum is total PF remitted, never labelled "employer cost"; fix the mirror-of-employee bug (statutory.ts:52–55). *(corrected 2026-11-21 post-review)* Keep "no EPS split for excluded members" consistent with pf-exclusion rules.
- **Frappe reference**: none in core (02 §5) — this is plain statutory math; india-payroll semantics used as spec.
- **Acceptance criteria**: (1) ceiling binds → EPS + remainder sum exactly to 12% of ceiling-wage; (2) excluded members → employer = employee figure as today (unchanged); (3) summary jsonb exposes employer PF separately; (4) payslip print gains an optional employer-PF line (non-deduction).
- **Size**: S–M (2–3 days). **ECR export is V1.x**, built on these columns.

### WI-E — Run preview (dry-run) + unmarked-day semantics + attendance gate
- **What**: (a) `POST /payroll/runs/preview` reusing the engine's compute pipeline with commit disabled — returns per-employee computed lines, totals, skip reasons, warnings (unmarked-day counts, missing PT rule, missing structure), plus aggregate employer cost incl. WI-D. Web: preview step before the enqueue button (Frappe's Create-Slips-then-review model, 04 §screens). (b) Make unmarked-day treatment explicit: constant or tenant setting (`unmarked_days_as: present | absent`, default present), surfaced in preview warnings. (c) Optional hard gate: block enqueue when unmarked days > threshold (Frappe's `validate_attendance` intent, minus its bug — 02 §8.3).
- **Frappe reference**: Payroll Entry two-step flow (02 §3, 04 §screens doc-payroll-entry-*.png); `consider_unmarked_attendance_as` (02 §2.2).
- **Acceptance criteria**: (1) preview totals == subsequent run totals for identical inputs (determinism pinned by test); (2) preview is read-only — no payslip rows, no lock interaction, no audit pollution (or audit-tagged `preview`); (3) warnings render in web; (4) unmarked-as-absent mode passes the 02 §7.6 anchor (8) matrix (test_salary_slip.py:188/252 semantics).
- **Size**: M (3–4 days). This is the safety centerpiece.

### WI-F — Salary register + bank advice exports (+ slip YTD)
- **What**: Two new entries in the existing reports registry (reports infra + R2 presign reuse): (a) **Salary Register** — month × employee grid, one row per employee: component columns (grouped by WI-B type), gross, each deduction, net, payable days, LOP days, employer PF; XLSX/CSV; (b) **Bank Advice** — employee, bank a/c, IFSC, amount (rounded net), reference (run id); CSV + printable summary. Add YTD earnings/TDS columns per employee (borrow #1's default_amount makes FY totals a SUM over run lines).
- **Frappe reference**: `salary_register` + `bank_remittance` reports (02 §5); rounding-remainder rule for totals (borrow #11).
- **Acceptance criteria**: (1) register column-sum of net == run summary net exactly; (2) bank advice rows == non-skipped employees with bank details; missing-bank-details employees appear in a warnings block; (3) exports respect tenant isolation + permissions (payroll.config-gated); (4) large-tenant performance: streaming/queue via report_requests like payslip PDFs.
- **Size**: M (3–4 days).

### WI-G — Payslip email delivery
- **What**: On run completion (or lock — pick ONE layer, borrow #8), enqueue notification emails to members with a stored email: template with gross/net/period + presigned PDF link (or attachment). Respect existing notifications infra + rate limits; missing email → skip reason surfaced in run summary, never an error (Frappe behaviour: msgprint-only, 02 §3.5). Optional tenant setting `payslip_email: off | on_completion`.
- **Frappe reference**: email_salary_slip + single-layer send flag (02 §3.5, §8.12); template rendering with slip context.
- **Acceptance criteria**: (1) one email per member per run even on re-run (dedupe by run-id+member, re-run regenerates the link rather than re-sending blindly — or re-sends with corrected PDF; decide + pin); (2) off-by-default until owner enables; (3) no PHI in logs.
- **Size**: S–M (2–3 days).

### WI-H — Admin payslip viewer (web-only, API shipped)
- **What**: Console panel: month picker → roster from `GET /payroll/payslips` (status, net, employee) → per-employee PDF via the existing admin POST; status badges (locked/available); empty states per Sally rules.
- **Reference**: 04 §screens (Frappe desk payslip list pattern); 03 §5 documents the unused API.
- **Acceptance criteria**: matches 03 §5's API contract without BE changes; mobile-safe layout not required (console is desktop-first).
- **Size**: S (1–2 days).

### WI-I — Off-cycle staging UI (web-only, API shipped)
- **What**: Write-side UI for off-cycle lines: add-line sheet (employee, amount +/−, tag, note, applies-to-month), validation against the shipped API, staged-lines list with source attribution (borrow #5 fields if added), impact hint ("applies to next run"). Clear the ledgered debt (03 App.A: deferred-work.md).
- **Reference**: 04 §screens (Additional Salary UI: amount, recurring, overwrite, impact preview).
- **Acceptance criteria**: staging → run → applied-line trace visible in one screen; negative lines capped preview shows 50%-cap effect (recovery roll-forward) before commit.
- **Size**: S–M (2–3 days).

### Explicitly NOT in V1 (decided)
ESI, LWF, declarations/regimes, gratuity, overtime, expense claims (separate epic), advance request flow, auto-arrears, hold/release, draft/approve stage, templates/branding, revision ledger, statutory hub UI, ECR export, accounting export — all verdicted above with triggers.

---

## 7. V1.x backlog (first wave after V1, with triggers)

| Item | Trigger | Anchor |
|---|---|---|
| ESI engine | any employee gross ≤ ₹21k | india-payroll spec; contribution periods Apr–Oct / Nov–Mar |
| PF ECR export | first tenant asks to file | WI-D columns; "Download ECR Text File" pattern (04) |
| Auto-arrears on backdated revision | first mid-year increment | Frappe Arrear doctype semantics (02 §1.2) → staged off-cycle lines |
| Overtime pay | first OT-heavy tenant | Frappe Overtime Slip model (02 §4.9) |
| Advance request/approval flow | first travel-advance ask | Fenzit recovery already better; add front door only |
| Slip-level YTD + tax breakup + mobile YTD hero | after WI-F YTD columns | Frappe Income Tax Breakup tab (04); Dashboard.vue YTD card |
| Recurring off-cycle amounts | first recurring-recovery ask | AS `is_recurring` (02 §4.3) |
| Monthly attendance sheet export | owner request | existing attendance grid |
| Hold/release per payslip | first exit-with-hold case | simplified `withheld` status (02 §7.2 recommends lite version) |
| LWP-reversal tool for locked months | policy decision needed first | Payroll Correction (02 §1.2) vs Fenzit's no-unlock policy |
| Accounting export (2-line journal-ready) | first CA integration ask | 02 §7.2 row 3 |
| Expense-claims epic | parallel track, owner's call | agent 1 row 27; pay OUTSIDE salary |

---

## 8. Risks & gotchas register for the implementer

From 02 §8 (24 verified Frappe gotchas), the ones that apply to Fenzit V1:

| # | Gotcha | Action for Fenzit |
|---|---|---|
| 02-§8.1 | Slab endpoints inclusive on both sides (`+1`) | WI-A slab table + validator; test boundary rupees |
| 02-§8.3 | Attendance gate ignores unmarked-as setting, counts holidays full-weight | WI-E: copy intent, not bug |
| 02-§8.6/7 | Overwrite/advance/recovery rows must NOT re-prorate | Already matches Fenzit off-cycle exact-amount model — preserve in preview (WI-E) |
| 02-§8.8 | TDS computed last, after exempted deductions | Verify Fenzit ordering; becomes load-bearing when exempted components (WI-B) exist |
| 02-§8.12 | Email fires at one layer only or doubles | WI-G hard rule |
| 02-§8.13 | Negative-net slips silently skipped in bulk runs | Never copy; Fenzit's cap+roll-forward stays |
| 02-§8.15 | Split-totals rounding remainder on last line | WI-F totals |
| 02-§8.20 | Zero remaining periods → guard division | Verify Fenzit final-run true-up already guards (offcycle-math handles remainder — pin with test) |
| 02-§8.2 | Denominator whole-period vs numerator DOJ-clipped inflates mid-joinee fraction | Known *different* model in Fenzit (cap keep-first); do not adopt Frappe's quirk; add a fixture asserting Fenzit's behaviour stays |
| Fenzit-local | canonical fixture September payable 25-vs-26 divergence adjudicated at run-window.ts:14–17 | Keep the adjudication comment when touching windows |

---

## 9. UI/UX action items for Sally (from 04)

Priority order, mapped to work items:

1. **Run page becomes two-step** (WI-E): "Preview run" → per-employee table + warnings + totals → "Commit". Mirror Frappe's Payroll Entry draft card (ui-shots/doc-payroll-entry-*.png).
2. **Admin payslip roster** (WI-H): month picker + roster grid + download; badge states locked/unlocked.
3. **Off-cycle staging sheet** (WI-I): component/tag picker, negative-amount warning showing the 50%-cap recovery preview, staged list with "applies to next run" hint.
4. **Exports section** (WI-F): Salary Register + Bank Advice cards with month picker and status (queued/ready) — reuse report_requests states.
5. **Structure editor**: third formula shape for state-conditional amounts (PT); formula-variable hint list like Frappe's editor autocomplete (bound variables: basic, payable days, gross).
6. **Payslip detail (mobile, V1.x)**: YTD hero reading FY totals, grouped earning/deduction sections, sticky Download PDF — pattern-transfers from Frappe ESS `Dashboard.vue`/`Detail.vue` (04 §mobile).
7. **Statutory hub (LATER)**: India Payroll-style page with per-statute cards (PF/PT/ESI/LWF) + status badges + "Download ECR" buttons (04 §screens india-payroll-1..5).

Design references: 34 screenshots under `ui-shots/` (22 product shots + 12 docs shots). Honest note from 04: no public Frappe demo credentials exist; screens verified from official product shots + docs + reading the ESS Vue source.

---

## 10. Recommended execution order

```
WI-A (TDS FY)          ─┐
WI-B (components)       ├─ foundation, week 1
                        ┘
WI-C (PT)   WI-D (PF split)   ── week 2 (parallel, both need WI-B)
WI-E (preview+gate)           ── week 2–3 (needs WI-B for line typing; benefits from WI-C/D for warnings)
WI-F (exports+YTD)            ── week 3 (needs WI-B; uses WI-E's preview determinism test)
WI-G (email)  WI-H (viewer)  WI-I (off-cycle UI) ── week 3–4 (parallelizable; H/I any time)
```

- **BMAD shape**: one epic ("Payroll V1 — Frappe-benchmarked must-haves"), 9 stories in WI order, each with the acceptance criteria above; statutory stories (C, D) get table-driven test specs before code.
- **Definition of done for the epic**: all 02 §7.6 anchor behaviours pinned as Fenzit specs; canonical fixtures unchanged (September 25 adjudication intact); every new table RLS-guarded with composite `(id, tenant_id)` FKs per repo convention.
- **Effort total**: ≈ 20–28 focused agent-days; biggest single risk is WI-E's preview determinism (engine currently has no dry-run path).

---

## 11. Post-V1 roadmap summary

V1.x wave (triggers above) → then, on demand: declarations + old regime + HRA + tax-breakup UX → gratuity + FnF worksheet → expense-claims epic (separate) → statutory hub + ECR + registers → overtime. The declaration track is the gateway to the whole "old regime" cluster — schedule it as one story cluster, not feature-by-feature.

*End of synthesis. Implementation starts only after owner review.*
