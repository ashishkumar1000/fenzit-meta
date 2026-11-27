# 26-1 — TDS tax-year parameterization

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | S–M (~1–2 days) · **build FIRST** |
| Layer | BE (fenzit-be) |
| Depends on | none |
| Contract | 05 §6 WI-A · 03 §10.B · 02 §2.5, §7.1.5, §8.1 |

## Gap (evidence)

The TDS estimator is new-regime FY 2026-27 **hardcoded in code**: slabs, s.157 rebate,
marginal relief, 4% cess live in `statutory.ts:132–176`, and the FY window
`2026-04…2027-03` is hardcoded at `engine:167-168` (03 §10.B). On **2027-04-01 every
slip computes wrong tax** unless a new FY is coded. There is also no way to seed
mid-year joiner openings (03 §10.B: estimator only).

## Scope

1. New table `payroll_tax_years`: `(id, tenant_id, fy_start, fy_end, slabs jsonb,
   standard_deduction, rebate_limit, rebate_upto_tax, marginal_relief_limit,
   cess_percent, surcharge_bands jsonb nullable, created/updated audit cols)` — one
   row per financial year per tenant, composite FKs + RLS per repo convention.
2. Month resolution mirrors the PF-ceiling idiom (month-start resolved): the run month
   must be covered by exactly one row.
3. **Refuse, don't extrapolate**: a run month without a covering row fails the run
   with a plain-English reason ("no income-tax year configured for 2027-04").
4. Move the FY 2026-27 constants into seed data (migration seeds the row for every
   tenant) and rewrite `statutory.ts` to read from the resolved row. Pure refactor —
   math unchanged.
5. Optional openings: accept `taxable_earnings_till_date` +
   `tax_deducted_till_date` and subtract them in the projection — for tenants
   onboarded mid-FY (borrow #4). **Storage pinned (review triage 2026-11-21):
   FY-keyed per member** — a small row `(id, tenant_id, membership_id, fy,
   taxable_earnings_till_date, tax_deducted_till_date)` mirroring Frappe's SSA layer
   (salary_structure_assignment.py:222-238 warns on missing openings). **Never store
   on `salary_structures` revisions** — structures are per-employee dated rows and a
   mid-FY revision would silently drop the openings → prior earnings vanish from the
   projection → under-deduction for exactly the population this serves. Identity:
   annual projection = openings.taxable_earnings_till_date + Σ current-FY Fenzit
   months' taxable; TDS spread = annual − openings.tax_deducted_till_date − Σ
   current-FY TDS.
6. **`tdsConfigView` (statutory.ts:106–124) renders the resolved tax-year row** (the
   month-resolution helper reused) — it currently hardcodes `taxYear: 'FY 2026-27'`
   plus the constants for the admin UI; without this the web surface would advertise
   stale numbers in April 2027 while runs use the table (caught in review).

## Out of scope

Old regime, regime choice, declarations/proofs, Form 16/24Q, challan tracking,
surcharge engine beyond a nullable bands field (all deferred with triggers, 05 §7).

## Technical approach

- Keep `statutory.ts` pure: pass the resolved tax-year row in; no DB reads inside the
  math (testable table-driven).
- Slab walk stays in Fenzit's existing implementation (rebate + marginal relief
  already correct, 03 §2.6); only the data source changes. **jsonb shape pinned**
  (review triage 2026-11-21): store slabs in the walk's own shape —
  `{upto: exclusiveUpper | null, rate}` (exclusive upper bound, implicit lower =
  previous `upto`; matches `TdsSlab` at statutory.ts:73–93). The validator checks:
  strictly-increasing `upto`, first slab starts at 0, and adjacent bands neither gap
  nor overlap the boundary rupee — the Frappe gotcha (02-§8.1, income_tax_slab.py:80-85
  adds `+1` per band) translates to: authoring `to = next_from − 1` inclusive pairs
  maps to `upto = to_amount + 1`; pin a boundary-rupee unit test (income 4,00,000 vs
  4,00,001).
- Openings subtract once (never double-taxed — Frappe pins this,
  test_salary_slip.py:2468 `test_opening_balances_excluded_from_tax_calculation`).

## Acceptance criteria

1. Seeded FY 2026-27 rows reproduce the canonical fixture **bit-for-bit** (every
   pinned money row unchanged: base 21,953.85, D-clamped 12,115.38, November
   26,876.93, Sep PF ceiling 1,800.00).
2. A synthetic FY 2027-28 row is resolved for April 2027 months; the 2027-04 boundary
   is journey-pinned.
3. Run month without a covering row → run status failed, plain-English reason, no
   silent extrapolation.
4. Openings accepted on config and subtracted exactly once; journey leg proves a
   mid-year joiner with openings is not double-taxed.
5. Slab-table validation rejects overlapping/misauthored tables with a 422.

## Test anchors

- 02 §7.6 (6) full-year TDS self-correction (`test_salary_slip.py:1483` semantics);
  (7) recurring additions projected (`:1614`).
- 02 §7.6 (5) future months ignore current LOP (`:2144`) — must keep holding.
- New: 2027-04 boundary; boundary-rupee slab validation; openings-once.

## References

Frappe: Income Tax Slab doctype w/ `effective_from` + per-slab conditions (02 §1.1);
slab resolution throws on disabled/unset and requires slab effective ≤ period start
(salary_slip.py:2074-2096); slab walk (income_tax_slab.py:47-101); SSA openings
warning (salary_structure_assignment.py:222-238).

## Risks / gotchas

- Canonical-fixture money rows must not move — the refactor is proven by bit-equality.
- Do not add a "regime" field yet (deferred) — keep the row schema forward-compatible
  but single-regime now.
- Tenant seeding: migration must seed existing tenants, not just new companies (mirror
  the 23-13 seed lesson: journey-caught missing seeds post-migration).
