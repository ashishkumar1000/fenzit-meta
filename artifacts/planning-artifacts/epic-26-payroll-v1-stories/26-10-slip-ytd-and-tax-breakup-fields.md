# 26-10 — Slip-level YTD + tax-breakup fields

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | S (~1–2 days) |
| Layer | BE (fenzit-be) |
| Depends on | 26-1 (tax-year table) + 26-6 (YTD math lands there first) + **26-2 soft** (`deductions_before_tax` needs the exempted tag; without it the field degrades to standard-deduction-only) |
| Contract | 05 §7 rows (promoted to V1 quick-win, owner 2026-11-21) · 03 §10.D · 02 §2.5 step 8, App.B, §7.1.1 |

## Gap (evidence)

Payslips are per-month only — **no YTD anywhere** and no income-tax breakup fields
(03 §10.D). Frappe stores breakup docfields on the slip itself: annual taxable,
standard exemption, declared exemptions, deducted-till-date, current month, future
deductions (compute_income_tax_breakup, salary_slip.py:1130-1178; full field list 02
App.B) — that's what makes a payslip self-defending when an employee disputes it, the
#1 owner-support driver the research flagged.

## Scope

1. Persist on the payslip snapshot, with per-number sources pinned (review triage
   2026-11-21):
   - `fy_ytd_earnings` = Σ FY run-line **earnings only** — 26-1's openings are
     tax-basis figures and are **excluded** (they are not gross earnings).
   - `fy_ytd_tds` = Σ FY run-line TDS **+** the 26-1 `tax_deducted_till_date` opening
     (the only opening that flows into a YTD column).
   - Breakup fields: `annual_taxable`, `standard_deduction_applied`,
     `deductions_before_tax` (26-2 exempted components), `tds_deducted_till_date`,
     `tds_current_month`, `tds_future_months`.
2. Snapshot semantics: fields freeze at lock like every other snapshot column
   (20261118000000 pattern); a re-run recomputes them.
3. Expose on the payslip DTO/view for mobile (26-11) and the admin roster (26-8).

## Out of scope

Employee-facing rendering (26-11 mobile; console later), declaration-based exemption
amounts (deferred cluster — standard deduction only for now), regime fields.

## Technical approach

- Two-number discipline (borrow #1): YTD = Σ `amount` across FY run lines (prorated
  reality), while full-cycle `default_amount` values remain available for the future-
  months projection — never recompute FY history from structures.
- Breakup reconciliation rule: `annual_taxable` must equal the 26-1 tax-year table's
  own projection basis for the same month (single source of truth = the table row's
  math, not a parallel estimator).
- Future-months projection reuses 26-1's resolved year row + full-cycle amounts
  (Frappe: future preview runs a full-cycle copy with payment_days = total_working_days
  — we compute from default_amounts without re-running the slip, 02 §8.9).

## Acceptance criteria

1. `fy_ytd_earnings` == Σ of that employee's FY run-line earnings exactly (openings
   excluded — pinned); `fy_ytd_tds` == Σ run-line TDS + `tax_deducted_till_date`
   opening (pinned; the mid-year-joiner journey leg proves the TDS opening flows in
   while earnings stay run-line only).
2. Breakup fields reconcile with the TDS actually deducted on the slip (identity
   test: current-month TDS field == the slip's TDS line).
3. Snapshot freeze/lock semantics respected; re-run recomputes (journey leg).
4. Zero-TDS months (below rebate) still carry coherent breakup fields (zeros, not
   nulls — pin the choice).

## Test anchors

- 02 §7.6 (5) future-months-ignore-current-LOP (`test_salary_slip.py:2144` semantics
  — the future projection must not embed this month's LOP).
- Breakup field population (`compute_income_tax_breakup`, salary_slip.py:1130-1178 —
  the original `:1857` cite was misattributed; caught in review triage).

## References

Frappe: compute_income_tax_breakup + compute_ctc + non-taxable earnings
(salary_slip.py:1130-1213); breakup docfields (02 App.B tax-breakup group); §7.1.6
(stored breakup gives auditors a defensible number without recomputation).

## Risks / gotchas

- Do not derive YTD by re-running past months' math — SUM stored lines only (the
  ownership-LOP model means historical recompute could legitimately differ).
- Snapshot column growth: keep jsonb vs columns decision consistent with the existing
  snapshot table shape (20261118000000 uses columns — follow it).
