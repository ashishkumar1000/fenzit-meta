# 26-3 — Professional Tax state engine

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | M (~3–5 days incl. seeding 5–8 states) |
| Layer | BE (fenzit-be) |
| Depends on | 26-2 (statutory tag) |
| Contract | 05 §6 WI-C · 03 §10.B · 01 §2b, row 12 |

## Gap (evidence)

**No PT model anywhere** (grep across src/payroll + migrations): a flat deduction head
can emulate a fixed monthly PT, but there are no state slabs, no half-yearly cycles,
no February doubling, no per-state registration; `payroll_state_rules` is a single
CoW-notified boolean, not a rules engine (03 §10.B). PT is the highest-frequency small
deduction in India — every tenant needs it on day 1.

## Scope

1. Table `payroll_pt_state_rules`: `(state, effective_from, monthly_slabs jsonb,
   half_yearly_amount, half_yearly_months jsonb, february_amount, max_monthly_cap)`
   — month-start resolution like the PF ceiling; effective-dated per state.
2. Employee PT state: auto-select from the employee's office state, with an explicit
   per-employee override field (nullable) for staff seated across states.
3. Engine: resolve the rule for the run month → compute the PT deduction for the
   payable days (prorated like other heads per the 26-2 flag) → deduction tagged
   `statutory_tag = 'pt'`.
4. Skip reason when unresolvable: plain-English "PT not configured for state X"
   (never silent).
5. Seed 5–8 common states at migration (Maharashtra, Karnataka, Tamil Nadu, West
   Bengal, Telangana/AP, Kerala, Gujarat…) with current slab tables.
6. Admin CRUD on the rules table (payroll.config), audit-written.

## Out of scope

PT *registration* numbers/certificates per state, filing reminders, LWF (same shape —
separate trigger), monthly attendance-based PT proration subtleties beyond the standard
payable-days proration.

## Technical approach

- Slabs keyed on gross (or CTG — gross salary minus PF where the state defines it that
  way; store a `basis` enum per state rule: `gross | gross_minus_pf` — MH/KA differ).
- February doubling states: the state rule expresses it as `february_amount`
  (replaces the monthly amount in Feb) — the Frappe docs idiom is a month-conditional
  formula (`300 if getdate(start_date).month in (6, 12)`), but we build a **rules
  table**, not admin-authored formulas (Fenzit's ledgered design; 04 §screens).
- Half-yearly states (e.g. AP/TS style June/December or similar): `half_yearly_amount`
  + `half_yearly_months` array — those months pay the lump sum, other months zero.
- `max_monthly_cap` enforced (₹200–₹2500 statutory band across states).
- Zero-PT months (below slab threshold): still emit the deduction row at 0 with
  remove-if-zero semantics? Decide: emit only when > 0 unless the tenant pins
  show-zero (mirror remove_if_zero_valued, 02 §2.4).

## Acceptance criteria

1. Maharashtra: standard-month slab correct + February amount replaces (not adds to)
   the monthly amount; cap binds at ₹2500.
2. Karnataka: PT applies only above the ₹25k gross threshold; below → 0/skip.
3. A half-yearly state pays the lump sum only in its configured months.
4. Employee in a state without a rule → skip reason "PT not configured for state X"
   in the run summary; per-employee override resolves it.
5. Table-driven per-state tests **written before code**; boundary-at-threshold case
   per state.
6. PT joins TDS's taxable base as a normal deduction (state PT is deductible under
   s.16(iii)) — pinned in a fixture row.

## Test anchors

- Boundary at gross threshold; February replacement; cap binding.
- Proration: PT prorates with payable days only if its component carries the 26-2
  flag (state-dependent — most states prorate; pin the default per rule).

## References

Frappe: month-conditional PT formula idiom in docs + india-payroll state engine
(01 §2b row 12; 04 §screens salary-structure PT example); our own 23-5 deduction-heads
pattern for the CRUD/audit shape.

## Risks / gotchas

- State slab data is legal data — seed tables must cite the source (effective date) in
  the migration comment; wrong slabs = wrong deductions at scale.
- Office-state auto-select must be deterministic when an employee has no office state:
  skip with reason, never a guessed state.
- February semantics differ per state (some double, some replace) — express both via
  the rule fields, don't hardcode February logic in the engine.
