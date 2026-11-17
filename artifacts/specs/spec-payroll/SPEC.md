---
id: SPEC-payroll
companions:
  - canonical-fixture.md
  - ../../planning-artifacts/research/domain-payroll-feature-scope-2026-11-16/research.md
  - ../../planning-artifacts/research/domain-payroll-feature-scope-2026-11-16/digests/code-audit-r3-1.md
  - ../../planning-artifacts/research/domain-payroll-feature-scope-2026-11-16/digests/statutory-gapcheck-r3-1.md
  - ../spec-human-readable-ids/SPEC.md
sources: []
---

> **Canonical contract.** This SPEC and `companions:` are the complete contract for what to build, test, and validate. `canonical-fixture.md` is the test oracle; the research report supplies conventions and market baseline; the code-audit digest supplies what exists and the patterns to reuse; the statutory digest supplies the operative legal basis — **on legal matters the statutory digest supersedes the research report**.

# Payroll — monthly salary processing with attendance-linked LOP

## Why

Fenzit tracks attendance and leaves but cannot turn them into pay: at month end a company admin has no way to generate salary slips, so LOP from excess leaves is applied by hand and statutory slips are produced outside the product (a pain to solve, plus an opportunity — attendance-first payroll is the market's entry wedge). Backdrop: Fenzit is pre-launch, India-first, single-sprint mindset with an explicit user direction to keep payroll simple — good-to-have features only, no enterprise HRMS complexity.

## Capabilities

- **CAP-1 — Salary component library**
  - **intent:** Company admin can define a company-level salary component library (e.g. basic, HRA, conveyance, special allowance) in the web admin.
  - **success:** A created component is assignable to employees; payslip lines snapshot the component name at the run that produced them; a component cannot be deactivated while any employee structure references it (rejected with the referencing employees listed); renaming is allowed and reflected from the next run.

- **CAP-2 — Employee salary structure (components, formulas, effective dating)**
  - **intent:** Company admin can set each employee's salary as an amount per component, where a component may instead be defined by a formula recomputed from other components (e.g. HRA = 40% of basic); structure changes carry an effective date and never overwrite history.
  - **success:** Employee A's structure (canonical fixture) computes gross ₹28,000 matching the fixture table; changing basic recomputes HRA at the next run without editing HRA; a mid-year revision effective from month M makes M's run use the new structure while prior locked months keep their snapshots (fixture variant F); a mid-month-dated revision takes effect from the next run; a formula cycle (A→B→A) is rejected at save with a plain-English error naming the chain (whole set re-checked on every edit); a formula whose operand has no amount in the employee's structure is rejected at save.

- **CAP-12 — Leave types for LOP**
  - **intent:** Admin can configure a leave-type catalog (each type marked paid or unpaid, e.g. casual/sick/earned/unpaid) on the existing leave feature; LOP in a run derives only from leaves of unpaid-marked types plus unapproved absences; paid-typed leaves never produce LOP in v1 (no leave-balance or accrual engine).
  - **success:** The canonical fixture (2 paid-typed + 3 unpaid-typed leaves + 1 unpaid half-day) yields LOP of exactly 3.5 days; reclassifying a type applies to runs executed after the change; locked months keep their snapshots; a paid-typed half-day produces no LOP.

- **CAP-3 — Monthly payroll run**
  - **intent:** Company admin can run a monthly payroll cycle (async, status polled) that computes each active technician-role membership's pay from the structure in effect, the month's day-status (LOP applied), and configured deductions; owners/admins and removed members are excluded unless explicitly configured in; employees with no effective structure or no attendance enrolment are skipped and flagged in the run summary — never a silent ₹0 payslip.
  - **success:** A run of the canonical fixture produces per-employee payslip rows exactly matching the fixture's expected-numbers table; mid-month join/exit auto-prorates per the run-arithmetic invariant (variants C and E); re-running the unlocked month replaces it cleanly — one payslip per employee, off-cycle lines preserved; a failed run leaves zero payslips (atomic per tenant-month); concurrent runs for the same month serialize; a zero-employee company completes with a zero-payslip run status; run months before the company's first payroll month or beyond the current cut-off are rejected.

- **CAP-4 — LOP divisor configuration**
  - **intent:** Company admin can set the LOP divisor convention (calendar days | fixed-30 | fixed-26, default fixed-26).
  - **success:** The canonical fixture under each convention produces its own distinct expected row (fixture months chosen so no two conventions coincide); switching the setting affects the next run only, never locked history.

- **CAP-5 — Half-day LOP**
  - **intent:** A half-day that produces LOP — an unpaid-typed half-day leave or an owner-corrected `half_day` day-status — counts as 0.5 LOP day.
  - **success:** An owner corrects a present day to half_day via the existing attendance-override path, then the run yields exactly half the single-day LOP deduction; the leave-part path matches the canonical fixture (3.5 total).

- **CAP-6 — Deduction heads + statutory auto-computation**
  - **intent:** Company admin can define deduction heads as flat monthly amounts or percentages with an admin-picked basis (basic | gross | CTC), applied per employee; the system additionally auto-computes PF — employee deduction 12% of the basic wages payable for the period (prorated for partial months), capped at the PF wage ceiling config; employer share recorded not deducted; company-level PF-covered switch default **off**; **new joiners are enrolled by default** (judicial line: SC *Pioneer* 2019 → Kerala HC *Sivasankaran* — post-first-coverage joiners above the ceiling cannot claim exclusion); the excluded-employee path (first-coverage grandfathering, never-a-member, Para 26(6)/26A option) is an admin configuration carrying an EPFO-flux warning; anyone ever previously an EPF member is always covered — and a new-regime TDS estimate for FY 2026-27 under the Income-tax Act, 2025: slab config (0–4L nil · 4–8L 5% · 8–12L 10% · 12–16L 15% · 16–20L 20% · 20–24L 25% · >24L 30%), standard deduction ₹75,000, resident-only s.157 rebate (₹60,000 = 100% of tax on income up to ₹12L, with marginal relief), 4% health & education cess; the estimated annual tax is spread over the **remaining months** of the financial year and re-estimated + re-spread when a revision or override changes the projection; the admin may override any computed amount behind an employer-liability acknowledgment.
  - **success:** The canonical fixture (PF on, PT ₹200) produces PF ₹1,800.00, TDS ₹0.00, net ₹22,230.77 exactly as tabled; a percentage head on gross applies to the payable post-LOP amount (variant B); an override changes only that amount after the acknowledgment; total deductions exceeding 50% of the wage-period base (post-LOP pre-deduction gross, including off-cycle earnings; employer shares outside the cap) are clamped at the cap with the excess raised as a recovery line on the next run's payslip — the cap check runs after overrides (variant D); a statutory value's effective-dated change applies from the next run and locked months keep the old values.

- **CAP-7 — Statutory payslip + self-service**
  - **intent:** The system generates a payslip per employee per run on the **central Form V template (Code on Wages (Central) Rules, 2026, rule 52)** — date of issue; establishment name + address; wage period; employee name, father's/mother's/spouse name, designation, UAN, bank account number; wage-rate break-up (basic / DA / allowances via the component structure); total attendance (paid days / days worked); overtime (₹0.00 in v1); gross wages payable; deductions (PF / ESI / others); net wages paid — plus the product extras: employee code (owner-set), PAN, date of joining, slip number (unique per tenant per salary period), payment date. This field set is authoritative for tests. Payslips are employee-visible **only after the month is locked** (admin previews pre-lock); regeneration of an unlocked month issues a new slip number and supersedes the prior PDF's presigned URL; a post-lock PDF retry regenerates the file only, never recomputes amounts; a missing PAN renders blank with an admin-visible warning, never a fabricated value.
  - **success:** The fixture payslip carries every Form V field plus the product extras; the employee opens their own payslip history and downloads the PDF and cannot open another employee's; a different company admin sees zero payroll rows for another tenant; re-running the unlocked month changes the slip number and invalidates the old URL.

- **CAP-8 — Payroll calendar**
  - **intent:** Company admin can configure the attendance cut-off day (default 25th, valid 1–28) and pay date (default 1st of next month, valid 1–7); all month boundaries resolve in the tenant timezone; attendance/leaves after the cut-off in month M count in month M+1's run as prior-period days.
  - **success:** Setting the cut-off to the 20th makes the run count only up to the 20th; a leave on the 27th (fixture G) appears in the next month's run; a pay date on/after the 7th is rejected with the CoW reason; a cut-off of 29/30/31 is rejected with the February reason; the pay date prints on generated payslips.

- **CAP-9 — Payroll lock**
  - **intent:** Company admin can lock a payroll month — permanent in v1, there is no unlock; the lock freezes the month against re-run, payslip edit, off-cycle targeting the month, and deduction-head edits affecting the month, each rejected with HTTP 409 `PAYROLL_MONTH_LOCKED`; the month-status API returns `locked: true`.
  - **success:** Each enumerated operation after locking returns 409 with that code; the month-status API exposes the lock for the web UI to render; the lock confirmation states its permanence and the off-cycle remedy.

- **CAP-10 — Off-cycle payout**
  - **intent:** Company admin can add a one-off earning (bonus, arrear, correction) for a specific employee in an unlocked month (current open or earlier unlocked); it is staged when that month has not run yet and appears on the month's payslip when it runs; off-cycle earnings join the wage-period gross for statutory computation and the 50% cap basis.
  - **success:** The off-cycle line appears on the chosen month's payslip included in gross and net (fixture G); no other employee's payslip changes; targeting a locked month is rejected (409); a staged line appears when the month first runs; a re-run keeps exactly one payslip with the line intact.

- **CAP-11 — Payroll audit trail**
  - **intent:** Every payroll-relevant change (structure, deduction heads, calendar, runs, lock, off-cycle) is recorded as who/what/when, viewable by company admin.
  - **success:** `GET` payroll audit events returns one entry per scripted edit, ordered by (created_at, sequence), each naming actor, action, and target — table-agnostic.

- **CAP-13 — Employment data for payroll**
  - **intent:** Company admin can capture, per employee in the web admin, exactly this field set — name, father's/mother's/spouse name (mandated by CoW Form V), PAN (validated format), date of birth, date of joining, PF account number, UAN number, designation, bank account number, IFSC code, bank name, employee ID (the tenant employee code, owner-set per `spec-human-readable-ids` CAP-4), department — plus exit date; existing active memberships are backfilled (admin-supplied or created_at-derived default); a removed membership without an exit date falls back to its status-change date.
  - **success:** Fixture variants C/E prorate from the join date; a run flags any employee with a missing joining date as skipped-with-warning (never null-prorates); exit date drives proration (variant C2); a missing PAN renders blank with a warning (CAP-7); every listed field is editable in the web admin and persisted against the membership/profile; DOB, PF/UAN, and bank details are never exposed to other employees.

## Constraints

**Legal (Code on Wages)**
- Governing law is the **Code on Wages** (in force 21 Nov 2025; central final rules 8 May 2026; state rules a variable overlay); verify the enacted text + target states' rules before legal freeze.
- Wage slips are mandated by CoW s.50(3) and prescribed by **Form V, rule 52 of the Code on Wages (Central) Rules, 2026** (Gazette 8 May 2026): issued electronically or physically **on or before payment of wages**; electronic issuance explicitly permitted. The finalised state rules adopt the identical model form — so the product ships the central Form V template plus a per-state "rules notified?" config switch, not per-state field sets (acceptance: CAP-7).
- Monthly wages payable **before the 7th** of the succeeding month, uniformly (no size carve-out).
- **Flat 50% total-deduction cap** per wage period, LOP included; cap base = post-LOP pre-deduction gross including off-cycle earnings, employer shares outside; breach clamps with an excess-recovery line (acceptance: CAP-6, variant D).
- No statutory literal in code — rates, ceilings, slabs, and the LOP divisor are effective-dated configuration.

**Run arithmetic (single formula)**
- Daily wage = structure amount ÷ divisor, unrounded. Payable days = calendar days of the employment window ∩ run month, **capped at the divisor**; week-offs and public holidays inside the window are paid days. Earnings = daily wage × (payable − LOP-equivalent days), floored at zero with any shortfall recorded for recovery via off-cycle payout. A full month with no LOP yields exactly the structure amount under every divisor.
- LOP-equivalent days = approved unpaid-typed leaves (half-day 0.5) **plus** day-status `absent` days with no approved leave, counted only inside the employment window; leave outside the window never LOPs; leave spanning months splits per-date by run month; `checkout_missing` is paid pending owner correction, flagged in the run summary.
- Money is `numeric(18,2)`; intermediates unrounded; half-up rounding applied once per payslip line. Formulas support component references, constants, `+ − × ÷`, and percent-of only; cycles are rejected at save (acceptance: CAP-2).
- Runs are idempotent per month and **atomic per tenant-month** (a failed run leaves zero payslips); concurrent runs for the same month serialize via the existing advisory-lock idiom, re-checking the lock before final commit; the run is async with a polled status; run months before the company's first payroll month or beyond the current cut-off are rejected; the tenant timezone governs the run window, cut-off, and pay date.

**Data & schema**
- Employment dates (join/exit) and the leave-type catalog are **new schema** on the existing membership/leave structures (no joining/exit data exists today; ~842 existing users backfilled per CAP-13).
- The run consumes the existing day-status engine (`src/common/day-status`, `summariseEmployeeMonth`, including owner corrections) — payroll never recomputes attendance.
- Attendance/leaves after the cut-off belong to the next month's run as prior-period days.
- All payroll FKs go through `memberships`; deny-by-default RLS with NestJS service-client access and explicit tenant filters; payslip access is owner-or-own; cross-tenant reads return zero rows (acceptance: CAP-7). No service-role keys in any frontend.
- Slip numbers reuse the house per-tenant sequence-counter idiom (`job_sequences` pattern: counter keyed `(tenant_id, salary_period)`, ON CONFLICT upsert, gap-free), allocated NestJS-first — no new SECURITY DEFINER RPC (AD-3).
- Statutory values (PF %, ceiling, slab table) are effective-dated config rows — acceptance in CAP-6.

**Reuse & platform**
- Payslip PDF rides the existing async report pipeline (report request → worker → pdfmake → R2 → presigned URL) — no new PDF machinery; employee visibility only after lock.
- All payroll configuration and administration lives in the **web admin (fenzit-web)**; the **mobile app (fenzit-app) is minimal — employee payslip self-service only** (own payslips + PDF). No payroll admin UI in the mobile app.
- Zero-RPC preference (AD-3 amendment): NestJS-first; any new RPC needs plain-English justification in the plan.
- Audit idiom (generic `audit_log` vs domain append-only) is picked in the plan — both precedented; CAP-11's acceptance is table-agnostic.
- Payslip employee-ID renders the tenant employee code, which the **owner sets and can edit** (amended `spec-human-readable-ids` CAP-4) — payroll owns no ID-generation logic.
- **Test anchor:** backend payroll stories extend `test/payroll-journey.e2e-spec.ts` (same real-DB helpers as the attendance journey suite: throwaway tenant, one API call + DB assert per step, FK-safe cleanup), seeded from `canonical-fixture.md`; the CAP-7 employee-visibility leg runs end to end; legs guard on real credentials.

## Non-goals

- Statutory filing engines: PF ECR, ESI challans, Form 24Q eTDS, Form 16 generation — admin serves these outside the product.
- Built-in state-wise PT/LWF slab tables; full tax computation (old-regime path, investment declarations, surcharge/annual recompute) — TDS stays a new-regime estimate.
- Leave-balance/accrual engine — LOP is type-based only (CAP-12).
- Loans & advances with EMI, F&F settlement workflow, leave encashment at exit, comp-off, overtime pay lines.
- Bank-transfer advice integration, email/WhatsApp payslip delivery (in-app + PDF only; electronic Form V delivery is compliant), legacy state wage-slip formats (e.g. Minimum Wages Rules Form XI) for draft-state tenants, maker-checker governance, AI features, contractor payments, multi-entity payroll, weekly/fortnightly pay cycles.
- Payroll admin UI in the mobile app (web admin owns all configuration).

## Success signal

A company admin, at month end, configures components and deduction heads once, runs payroll, and every employee's payslip — LOP from their actual leaves, prorated for mid-month joins/exits, statutory PF/TDS computed with admin override — is generated, lockable, and visible to that employee in the mobile app with a PDF download. A second run on the same month produces the same numbers until config changes. The canonical fixture's expected-numbers table holds exactly.

## Assumptions

- Company admin runs payroll; platform super admin has no payroll UI in v1.
- All employee roles in scope; user-facing copy says "Employee".
- Leaver final pay is issued on the normal monthly run for their exit month — the CoW s.17(2) two-working-day F&F timeline is a documented v1 divergence, accepted pre-launch.
- Whole-month rule for revisions: a mid-month-dated structure change takes effect from the next run (no half-month apportionment).

## Open Questions

- **TDS s.192 employer obligation** — the *method* is verified (estimate annual salary income, apply slabs, spread over remaining months — practitioner standard, CalcGuru Jul 2026); still open: the bare s.192/201 statutory wording and whether any small-employer exemption exists, before relying on the estimate + override posture in user-facing compliance copy.
- **EPFO excluded-employee flux** — EPFO administration keeps pushing the exclusion reading for above-ceiling joiners (Feb 2025 circular withdrawn Apr 2025; Jul 2025 draft unnotified) while the judicial line (SC *Pioneer* 2019, Kerala HC *Sivasankaran* 2018/19) supports mandatory enrollment; the product default follows the judicial line with a config flag for the flux. Confirm before legal freeze.
- **EPFO circular primary text** — the mid-month contribution rules (15+ wage-days → full month; <15 days → pro-rata) trace to the HRM-4(2)17/2014/SS-III series (27.01.2017 order — /125 vs /1584 number unconfirmed) and an 08.08.2018 circular; read the primary PDFs (e.g. `eGov_ROHyd2.pdf`) before citing any number in user-facing copy.
- **Legacy-value switch in statutory config** — the wage-ceiling config must carry the historical ₹15,000 (pre-2026-09-17) alongside ₹25,000 with the S.O. 5109(E) effective date, so runs for locked/pre-September months compute on the correct historical value.
