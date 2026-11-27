# Epic 26 — Payroll V1: Frappe-benchmarked must-haves

Registered 2026-11-21 from the overnight Frappe HRMS benchmark (owner direction:
"create a epic and add stories to it .. we will do development later"). The contract
for every story below is the benchmark report set — read before building:

- `artifacts/planning-artifacts/payroll-v1-frappe-benchmark-2026-11-21/00-EXEC-SUMMARY.md` — verdicts + decisions
- `…/05-gap-analysis-v1-plan.md` — the master plan: §6 = per-story scope + acceptance criteria, §5 = what to borrow from Frappe, §8 = gotcha register, §10 = sequencing
- `…/02-frappe-payroll-engine-internals.md` — Frappe mechanics with file:line (cloned at `workspace/external/frappe-hrms` @ ea4158c4, read-only)
- `…/03-fenzit-payroll-current-state.md` — our current code with file:line; §10 checklist = the gap evidence
- `…/04-ui-ux-reference.md` + `ui-shots/` — UI patterns for the web stories

## Mission

Close the verified gaps between Fenzit payroll and the India-SMB payroll must-have
bar (Frappe-validated), without regressing the engine properties where Fenzit is
already ahead. Fourteen stories (9 must-haves + 5 owner-approved quick-win polish,
2026-11-21), ≈24–32 agent-days (26-7 re-sized M after review: no email transport
exists today). Deployment order: BE stories 1–7 first (fenzit-be
deploys first), web-only 8/9/14 parallelizable anytime, polish 10–13 as marked.

## Protect these — do NOT "catch up" to Frappe (05 §4)

- Permanent month lock (Frappe cancels/deletes; we never add an unlock)
- Append-only audit trail + actor attribution
- Ownership-LOP + payroll-date gating for backdated corrections
- 50% deduction cap + recovery roll-forward (Frappe silently skips negative-net slips — never copy)
- Computed PF with dated ceiling; advisory-lock serialization; idempotency-keyed writes; RLS tenancy
- Plain-English skip reasons surfaced in run summary (vs Frappe's silent skips)

## Stories

**Every story has an enriched dev-ready card under
`epic-26-payroll-v1-stories/`** (same folder as this file) — gap evidence with
file:line, scope, out-of-scope, technical approach, numbered acceptance criteria,
test anchors, Frappe references, risks. **Read the card before building**; the
bullets below are the index.

- **26-1-backend-tds-tax-year-parameterization** (S–M, no deps — build first)
  FY 2026-27 constants (slabs at statutory.ts:85–93, standard deduction :96, rebate
  threshold :99, cess :100 — applied in `annualTax` :132–176; no surcharge exists in
  code, `surcharge_bands` is a nullable forward-compat field; engine FY hardcode at
  :167–168) into a `payroll_tax_years` table keyed (tenant_id, fy_start, fy_end);
  month resolution picks the covering row; refuse to run months without one (fail
  loudly, never extrapolate); `tdsConfigView` renders the resolved row. Acceptance:
  seeded 2026-27 rows reproduce canonical fixture bit-for-bit; synthetic 2027-28 row
  picked up for April 2027; missing-row run fails with plain-English reason; openings
  stored FY-keyed per member (never on structure revisions) and subtracted once.
  Borrow #4 + gotcha 02-§8.1 (slab boundary-rupee rule; jsonb shape = the walk's
  exclusive-`upto` form). Test anchors: 02 §7.6 (6) tax self-correction, (7) recurring
  additions, (5) keeps holding; add the 2027-04 boundary.

- **26-2-backend-component-type-taxonomy** (M, no deps — foundation for 3/4/6)
  One unified component model with `type` enum (earning | deduction |
  employer_contribution), statutory tag (pf | pt | tds | esi | lwf | null), and
  `prorates_with_payable_days` boolean; migrate existing earning components +
  deduction heads; keep exactly-one-basic rule; add `exempted_from_income_tax` —
  wired now (excluded from the taxable base, deducted before TDS per gotcha 02-§8.8),
  not just forward-compat. Acceptance: all existing runs re-render identically post-migration;
  register (26-6) can group by type; PT (26-3) and PF split (26-4) tag without new
  tables. Flags subset only — no statistical/flexible/accrual flags (02 §7.2).

- **26-3-backend-professional-tax-state-engine** (M, needs 26-2)
  `payroll_pt_state_rules` (tenant-scoped: id, tenant_id, state, effective_from,
  monthly_slabs jsonb, half_yearly_amount, february_amount, max_annual_cap);
  month-start resolution like the PF ceiling; employee PT state auto-selected from
  office state with explicit per-employee override; deduction tagged `pt`.
  Acceptance: Maharashtra ₹200/month + **February ₹300** (replacement — NOT a
  doubling; ₹2,500 is the statutory ANNUAL cap, Art. 276(2), max monthly ₹300);
  Karnataka >₹25k-gross-only rule testable; employee without a state rule → skip
  reason "PT not configured for state X"; half-yearly states (Kerala; MP is the
  gross-minus-PF basis case) supported. Table-driven per-state tests before code;
  boundary-at-gross-threshold case.

- **26-4-backend-pf-employer-split** (S–M, needs 26-2)
  Compute EPS (8.33% of min(earned basic, ceiling)) + EPF remainder (12% − EPS) per
  member per run; store employee/EPS/remainder on run lines; **employer PF
  contribution = EPS + remainder (= the employee figure, 12%)** — the three-column
  sum is total PF remitted, never labelled "employer cost"; FIX the mirror-of-employee
  bug (statutory.ts:52–55 — "v1: no EPS split" recorded the employer as a copy of the
  employee figure). Acceptance: ceiling binds → EPS + remainder = 12% of ceiling-wage
  exactly; excluded members unchanged; summary jsonb exposes employer PF (12%);
  optional employer-PF line on the payslip print (non-deduction). ECR export is
  explicitly deferred (V1.x, trigger: first 10+ PF member tenant asks to file).

- **26-5-backend-and-web-run-preview-plus-unmarked-day-semantics** (M, after 2/3/4 for
  richer warnings)
  (a) `POST /payroll/runs/preview` — engine compute pipeline with commit disabled;
  per-employee computed lines, totals, skip reasons, warnings (unmarked-day counts,
  missing PT rule, missing structure), aggregate employer cost; read-only (no payslip
  rows, no lock interaction, preview-tagged audit only); web: preview step before the
  enqueue button (Frappe's Create-slips-then-review flow, ui-shots/doc-payroll-entry-*).
  (b) Explicit `unmarked_days_as: present | absent` setting (default present) surfaced
  in preview warnings — verify current run-lop.ts behaviour first; missed punches are
  constant in field service. (c) Optional hard gate on unmarked days > threshold —
  copy Frappe's validate_attendance INTENT without its bug (gate ignores its own
  setting + counts holidays full-weight, 02 §8.3). Acceptance: preview totals ==
  subsequent run totals for identical inputs (determinism pinned by test); warnings
  render in web; unmarked-as-absent passes the 02 §7.6 (8) matrix.

- **26-6-backend-and-web-salary-register-and-bank-advice-exports** (M, needs 26-2;
  leans on 26-5's determinism test)
  Two new reports-registry entries reusing the report_requests → R2 presign pipeline:
  Salary Register (month × employee grid: component columns grouped by type, gross,
  deductions, net, payable days, LOP days, employer PF; XLSX/CSV) and Bank Advice
  (employee, bank a/c, IFSC, rounded net, run reference; CSV + printable summary).
  FY YTD earnings/TDS columns per employee (YTD = Σ payslip-snapshot sums; TDS column
  adds the 26-1 tax-deducted-till-date opening — openings never mix into earnings).
  Acceptance: register column-sum of net == Σ payroll_payslips.net_wages for the month
  exactly (rounding-remainder rule, borrow #11); bank advice rows == non-skipped
  employees with bank details, missing-details employees in a warnings block; minting
  via dedicated payroll.config-gated payroll routes (23-8 plain-insert pattern);
  streaming/queued for large tenants.

- **26-7-backend-payslip-email-delivery** (M — includes a minimal outbound-email
  transport; the notifications module is an in-app inbox only, no send path exists —
  review-verified 2026-11-21)
  On run completion OR lock — pick ONE layer (invariant: one email per member per run;
  Frappe doubles without its via_payroll_entry flag, 02 §8.12) — send emails with
  gross/net/period + PDF **attachment** (shipped presign TTL is 600 s; emailed links
  die in 10 minutes with no re-issue path for staff without the app); tenant setting
  `payslip_email: off | on_completion` (off by default); missing email → skip reason
  in run summary via post-commit update, never an error; no PHI in logs. Re-run:
  re-send only when the member's payslip snapshot changed.

- **26-8-web-admin-payslip-viewer** (S, web-only — any time; BE ships already)
  Console panel on the UNUSED API from 23-8 (GET /payroll/payslips admin month roster +
  admin PDF POST): month picker → roster with status badges (locked/available) →
  per-employee PDF. No BE changes; desktop-first; honest empty states per Sally rules.

- **26-9-web-off-cycle-staging-ui** (S–M, web-only — any time; BE ships already)
  Write-side UI for off-cycle lines (clears the ledgered debt from 23-11/deferred-work.md):
  add-line sheet (employee, signed amount, tag, note, applies-to-month), validation vs
  the shipped API, staged list with source attribution, impact hint "applies to next
  run", negative-line preview showing the 50%-cap recovery effect before commit.
  Staged → run → applied trace visible in one screen.

## Quick-win polish (owner-approved 2026-11-21, ≈+3 days total)

- **26-10-backend-slip-ytd-and-tax-breakup-fields** (S, after 26-1 + 26-6)
  Persist FY YTD earnings/TDS + income-tax breakup fields (annual taxable, standard
  deduction/exemptions, deducted-till-date, current month, future projection) on the
  payslip snapshot/lines. Two-number discipline from borrow #1: YTD must equal the SUM
  of run lines across the FY; breakup must reconcile with 26-1's tax-year table math.
  Serves 26-11's hero and future employee-facing breakup display; employees disputing
  payslips was the #1 owner-support driver the research flagged.

- **26-11-mobile-payslip-ytd-hero** (S, fenzit-app, after 26-10)
  Payslips home: YTD hero card reading FY totals + FY selector (April–March),
  grouped earning/deduction sections, sticky Download PDF. Pattern-transfer from
  Frappe's ESS `Dashboard.vue`/`Detail.vue` (04 §mobile, ui-shots/mobile-salary.webp).
  done_checkpoint: device pass.

- **26-12-backend-and-web-recurring-off-cycle-amounts** (S, extends 26-9 + the 23-9 API)
  `from_month`/`to_month` recurrence on staged lines — pinned representation:
  **expand-at-staging** into one off-cycle row per covered month (shipped single-month
  schema untouched; flip/re-target/orphan/idempotency keep working per-row) (Frappe AS
  `is_recurring` window semantics — recurring match = window overlap with the pay
  period, 02 §4.3). Acceptance: staged line applies N months; cancel stops future
  months without touching already-applied ones; locked month in the window → 409
  PAYROLL_MONTH_LOCKED; 50%-cap and recovery roll-forward interplay unchanged; re-run
  of a covered month is idempotent.

- **26-13-backend-and-web-attendance-sheet-export** (S, independent — any time)
  Monthly attendance sheet CSV/XLSX from the existing day-status grid via the reports
  registry (employee × day-status columns, LOP/unpaid flags highlighted). Owners close
  attendance before payroll — mirrors Frappe's documented flow. Acceptance: export ==
  grid exactly; payroll.config-gated.

- **26-14-web-report-queue-pause-ui** (S, web-only — any time; API ships since 23-8)
  Console UI for the shipped pause surface (GET status / POST pause 1–1440-or-forever
  / POST resume): pause card with duration picker, active-pause banner on the reports
  surface, resume action. The 23-8 follow-up explicitly ledgered this as a future FE
  story; honest empty states per Sally rules.

## Explicit non-goals in V1 (deferred with triggers — 05 §7)

ESI (trigger: any employee gross ≤ ₹21k) · PF ECR export (trigger: first 10+ PF-member
tenant files) · LWF (second state ask) · auto-arrears on backdated revision · overtime ·
advance request flow · hold/release ·
LWP-reversal for locked months (policy question first) · accounting export ·
declarations/old regime/HRA (one story-cluster later) · gratuity · expense claims
(owner to confirm: separate epic after V1, per 00-EXEC-SUMMARY decision 3) ·
payslip templates/branding · revision ledger · statutory hub UI · draft/approve stage ·
Form 16/24Q.

## Working rules (binding, from CLAUDE.md)

- No commit without owner consent; BMAD code review before any commit; bun only.
- Every fix/choice states FE vs BE vs DB owning layer first (root cause + long-term contract).
- Statutory stories (26-1/3/4): table-driven test specs BEFORE code; extend
  test/payroll-journey.e2e-spec.ts from the canonical fixture; canonical-fixture money
  rows must not change (September 25 adjudication at run-window.ts:14–17 stays).
- All new tables RLS-guarded with composite (id, tenant_id) FKs per repo convention;
  payroll.config owner-only permission for admin surfaces; audit every mutation via the
  payroll.* writer.
- Never weaken an assertion to match buggy behaviour; respect the §8 gotcha register
  (inclusive slab endpoints; TDS computed last; email one-layer; no silent skips).
- Frappe references are for semantics only — Fenzit's compiled AST engine, monthly-only
  frequency, INR-only, and lock/audit model always win over porting Frappe machinery.
