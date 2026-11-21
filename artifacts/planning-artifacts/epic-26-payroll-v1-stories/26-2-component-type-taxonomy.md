# 26-2 — Component type taxonomy

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | M (~2–3 days) |
| Layer | BE (fenzit-be) |
| Depends on | none (foundation for 26-3, 26-4, 26-6, 26-10) |
| Contract | 05 §6 WI-B · 03 §10.A · 02 §2.4, App.C |

## Gap (evidence)

Components are **earnings-only** (name + basic + active — migration 20261117120000)
plus a separate deduction-heads table (payroll_deduction_heads, 23-5); there is no
unified earning/deduction/employer taxonomy and no statutory tag (03 §10.A). PT
(26-3), PF employer split (26-4), and register grouping (26-6) all need one.

## Scope

1. One unified component model exposed to the engine and the register:
   - `type` enum: `earning | deduction | employer_contribution`
   - `statutory_tag`: `pf | pt | tds | esi | lwf | null`
   - `prorates_with_payable_days` boolean (earnings only)
   - `exempted_from_income_tax` boolean (forward-compat for future declarations)
2. Migrate existing earning components + deduction heads onto the model **in place**
   (views or a merged table — implementer's choice; keep the shipped API contracts of
   23-3/23-5 working).
3. Keep the exactly-one-basic rule (partial unique index 20261117140000:14-16 + the
   service probe) unchanged.
4. Admin CRUD, audit (`payroll.*` writer), and payroll.config permission preserved.

## Out of scope

New component *kinds* of Frappe flag surface: no statistical, flexible-benefit,
accrual, do-not-include-in-accounts flags (02 §7.2 over-engineering list). No
employer-contribution *table* on payslips (26-4 stores columns, not a third parentfield).

## Technical approach

- Flags adopted now = Frappe's load-bearing subset (02 App.C persistence set minus
  benefit/accrual flags). Every payslip line persists its component's flag snapshot so
  later flag edits never mutate locked months (consistent with Form V snapshot rule).
- **Double-proration guard** (port of salary_structure.py:130-149): reject
  `prorates_with_payable_days` on a formula line whose formula references another
  prorated component's abbr — dependents inherit prorated bases instead (borrow #2).
  Pin with a test: SA = BS × 0.5 must prorate exactly once (02 §7.6 (4),
  test_salary_slip.py:808 semantics).
- TDS remains `statutory_tag = 'tds'`, computed last (gotcha 02-§8.8 ordering) —
  becomes load-bearing once `exempted_from_income_tax` exists.

## Acceptance criteria

1. All existing runs re-render **identically** post-migration (canonical fixture
   bit-for-bit; journey 73/73-style green).
2. The register (26-6) can group/aggregate by `type` without schema work.
3. PT (26-3) and PF split (26-4) attach via `statutory_tag` with **no new tables**.
4. A formula line referencing a prorated abbr cannot also carry the prorates flag
   (422 at save); dependent-inheritance pinned by test.
5. `exempted_from_income_tax` components are excluded from the taxable base and
   deducted before TDS (ordering test).

## Test anchors

- 02 §7.6 (4) dependent-component single proration (`test_salary_slip.py:808`).
- Ordering: tax computed last after exempted deductions (02 §8.8).

## References

Frappe Salary Component type + 24 flags (02 §2.4); SALARY_COMPONENT_FLAGS persistence
set (02 App.C); India regional `component_type` select (Provident Fund/Professional
Tax, 02 §5).

## Risks / gotchas

- Migration touches the money path — bit-equality proof is the gate, not eyeballing.
- Don't break the 23-3/23-5 web console contracts in the same commit; if the merged
  model changes shapes, that's a follow-up web story, not silent API drift.
- Keep `payroll_state_rules` (CoW boolean) untouched — it's a labour-law flag, not a
  component taxonomy concern.
