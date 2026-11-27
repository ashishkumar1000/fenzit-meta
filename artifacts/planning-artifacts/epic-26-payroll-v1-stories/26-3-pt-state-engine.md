# 26-3 — Professional Tax state engine

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | M (~3–5 days incl. seeding 5–8 states) |
| Layer | BE (fenzit-be) |
| Depends on | 26-2 (statutory tag) |
| Contract | 05 §6 WI-C · 03 §10.B · 01 §4 row 12 (statutory figures web-verified 2026-11-21: Maharashtra & Karnataka PT schedules, Karnataka Act 14 of 2023, Art. 276(2) cap) |

## Gap (evidence)

**No PT model anywhere** (grep across src/payroll + migrations): a flat deduction head
can emulate a fixed monthly PT, but there are no state slabs, no half-yearly cycles,
no February doubling, no per-state registration; `payroll_state_rules` is a single
CoW-notified boolean, not a rules engine (03 §10.B). PT is the highest-frequency small
deduction in India — every tenant needs it on day 1.

## Scope

1. Table `payroll_pt_state_rules`: `(id, tenant_id, state, effective_from,
   monthly_slabs jsonb, half_yearly_amount, half_yearly_months jsonb,
   february_amount, max_annual_cap)` — **tenant-scoped** per repo canon (composite
   FK + RLS + payroll.config CRUD, matching the epic's binding rules; the original
   sketch omitted tenancy — caught in review). Month-start resolution like the PF
   ceiling; effective-dated per state.
   **Seed strategy pinned**: the migration seeds per-tenant rows for every seeded
   state (cheap — ~8 rows/tenant, mirrors the 26-1 tax-year seeding); owner CRUD
   edits their own copy; rows for states the tenant doesn't operate in are inert.
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

- Slabs keyed on a per-state `basis` enum: `gross | gross_minus_pf`. Maharashtra and
  Karnataka are both **monthly-gross**; Madhya Pradesh is the `gross_minus_pf` case
  (salaried PT on salary after PF deduction) — verified 2026-11-21 (the original
  "MH/KA differ" attribution was wrong).
- February states (Maharashtra ₹200 → ₹300 in Feb; Karnataka >₹25k ₹200 → ₹300 in
  Feb): the state rule expresses it as `february_amount` which **replaces** the
  monthly amount in Feb — NOT a doubling (₹2,500 is the statutory **annual** total
  under Art. 276(2); the max monthly PT is ₹300). The Frappe docs idiom is a
  month-conditional formula (`300 if getdate(start_date).month …` — February-
  conditional), but we build a **rules table**, not admin-authored formulas
  (Fenzit's ledgered design; 04 §screens).
- Half-yearly salaried-PT states: **Kerala** (instalments due 31 Aug / 31 Jan — needs
  `half_yearly_amount`/`half_yearly_months`, not monthly slabs) and **Madhya
  Pradesh** (also the basis case). AP/Telangana salaried PT is monthly — the original
  "AP/TS half-yearly" attribution was wrong (review 2026-11-21).
- `max_annual_cap` enforced per employee per FY (default ₹2,500 — the Art. 276(2)
  constitutional ceiling; the original `max_monthly_cap` at "₹200–₹2500" could never
  bind and was a false safety).
- Zero-PT months (below slab threshold): still emit the deduction row at 0 with
  remove-if-zero semantics? Decide: emit only when > 0 unless the tenant pins
  show-zero (mirror remove_if_zero_valued, 02 §2.4).

## Acceptance criteria

1. Maharashtra: standard month ₹200, February **₹300** (replacement, not addition —
   11×200 + 300 = ₹2,500/year); Karnataka >₹25,000: ₹200/month, Feb ₹300; annual
   total per employee never exceeds ₹2,500 (Art. 276(2) — `max_annual_cap` binds).
2. Karnataka: PT applies only above the ₹25k gross threshold; below → 0/skip.
3. A half-yearly state pays the lump sum only in its configured months.
4. Employee in a state without a rule → skip reason "PT not configured for state X"
   in the run summary; per-employee override resolves it.
5. Table-driven per-state tests **written before code**; boundary-at-threshold case
   per state.
6. PT joins TDS's taxable base as a normal deduction (deduction from salary under
   **s.19(2), Income-tax Act 2025** — the 1961 Act's s.16(iii) equivalent; the repo's
   operative act is the 2025 Act per statutory.ts:71/:98) — pinned in a fixture row.

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
