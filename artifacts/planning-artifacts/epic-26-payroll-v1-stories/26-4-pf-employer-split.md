# 26-4 — PF employer split + correct employer recording

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | S–M (~2–3 days) |
| Layer | BE (fenzit-be) |
| Depends on | 26-2 (statutory tag) |
| Contract | 05 §6 WI-D · 03 §10.B · 02 §5 |

## Gap (evidence)

The employer PF figure is **factually wrong today**: `statutory.ts:52–55` ("v1: no EPS
split") records the employer contribution as a **mirror of the employee figure**. Real
split: of the employer's 12%, EPS takes 8.33% of the ceiling wage (₹15k/₹25k dated)
and the remainder goes to EPF; above the ceiling wage everything above EPS goes to
EPF. Coverage rules already exist and are correct (pf-config.service.ts:144-151,
pf-exclusion.service.ts:110-118).

## Scope

1. Compute per covered member per run:
   - `pf_employee` = 12% × min(earned basic, ceiling) (unchanged)
   - `pf_eps` = 8.33% × min(earned basic, ceiling)
   - `pf_epf_remainder` = `pf_employee` − `pf_eps`
   - employer cost = `pf_employee + pf_eps + pf_epf_remainder` (= employee × 2, but
     now with the *correct* statutory composition)
2. Store the three columns on run lines (additive — existing pinned rows untouched).
3. Run summary jsonb exposes employer PF separately from employee PF.
4. Payslip print gains an optional employer-PF line, explicitly non-deduction
   (informational; Frappe hides employer contributions from the printed slip by
   default — test_employer_contributions_not_printed, test_salary_slip.py:3906 — we
   show it as a labelled info line; decide + pin).
5. Excluded (never-member) members: unchanged behaviour (no PF either side).

## Out of scope

EPF ECR/challan export (V1.x, trigger: first 10+ PF-member tenant files); UAN
validation/EPFO linking; PF loan/advance-withdrawal accounting; pension math beyond
the EPS split (scheme certificates etc.).

## Technical approach

- Pure statutory math extension in `statutory.ts` (keep pure, table-driven testable),
  no Frappe reference needed — Frappe core has **no PF math at all** (02 §5: admins
  write formulas); india-payroll semantics used as the spec.
- Rounding: compute EPS and remainder from unrounded values; remainder absorbs the
  rounding remainder so `employee = eps + remainder` holds exactly at paise level
  (borrow #11 remainder-on-last-line rule).
- Ceiling: reuse the dated ceiling resolution (₹15k → ₹25k from 2026-09-17,
  month-start resolved) — same function, no new date logic.
- Wage tag: only wage-tagged amounts join the PF base (bonus never — existing rule
  from 23-9, keep).

## Acceptance criteria

1. Ceiling binds → `pf_eps + pf_epf_remainder == pf_employee` exactly (paise-exact)
   and EPS == 8.33% of min(earned basic, ceiling).
2. Above-ceiling case: EPS stays 8.33% × ceiling wage; remainder grows with the
   employee share.
3. Excluded members: all three columns null/zero as today; no employer figure.
4. Canonical fixture: every existing pinned PF row **identical** (Sep ceiling
   1,800.00); new EPS/remainder columns additive and owner-confirmed before lock.
5. Summary jsonb + payslip info line verified; journey legs added.

## Test anchors

- Table-driven: below-ceiling, at-ceiling, above-ceiling, excluded, leaver final run.
- Fixture pin stays (Sep ceiling 1,800.00).

## References

Frappe: employer contribution as a distinct component type with its own JE (02 §3.4b)
— we keep columns, no JE layer; india-payroll EPF semantics as spec (01 row 13).

## Risks / gotchas

- The "employer = 2 × employee" simplification some owners assume is true in total but
  wrong in composition — the summary must label the split explicitly.
- Do not touch the employee-share math; this story is additive columns only.
- Payslip info line must never read as a deduction (visual + template test).
