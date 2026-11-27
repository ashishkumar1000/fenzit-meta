# 26-12 — Recurring off-cycle amounts

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | S (~1 day) |
| Layer | BE (fenzit-be) + web (fenzit-web, extends 26-9's sheet) |
| Depends on | 26-9 for the UI surface (BE can land first against the API) |
| Contract | 05 §7 rows (promoted to V1 quick-win, owner 2026-11-21) · 03 §2.9 · 02 §4.3 |

## Gap (evidence)

Off-cycle staged lines are **single-month only** — a ₹2,000/month deduction for 6
months means staging 6 lines by hand. Frappe's Additional Salary has `is_recurring`
with a `from_date/to_date` window: one row, picked up by every pay period overlapping
the window (02 §4.3: recurring match = `from_date <= end_date AND to_date >= end_date`;
disabled rows ignored; overlapping recurring rows blocked — test_additional_salary.py:263).

## Scope

1. Staged lines gain optional `to_month` (+ the existing applies-to-month as
   from_month): a line with `to_month >= from_month` recurs monthly through `to_month`.
2. Engine: each covered month's run absorbs the line once (existing staged→applied
   flip extends per-month — a 6-month line creates 6 applied rows, one per covered
   run, by exact captured id+month set).
3. Cancel semantics: cancelling the staged line stops **future months only**; already-
   applied months are untouched (applied lines immutable — existing rule).
4. Re-run idempotency: re-running a covered month doesn't double-absorb (the 23-9
   re-run merge/idempotency rules extend per month).
5. Web (26-9's sheet): recurrence toggle + end-month picker + "applies to N runs"
   hint; cancel dialog states the future-months-only consequence in plain English.

## Out of scope

Non-monthly frequencies (weekly etc. — never), retroactive recurrence into locked
past months (locked = untouchable, existing rule), variable-per-month amounts
(recurrence is a fixed amount per month), Frappe's overwrite flag (LATER with
auto-arrears).

## Technical approach

- **Representation pinned (review triage 2026-11-21): expand-at-staging** — staging a
  recurring line creates **one `payroll_off_cycle_lines` row per covered month** (the
  shipped single-`month` / single-`status` schema is untouched, so the exact-captured-
  id flip, re-target, orphan listing, idempotent POST, and the 409/422 matrix all keep
  working per-row, and the engine's `.eq('month', month)` read needs no change). The
  staged list groups the clones under one logical line; re-target mid-window re-targets
  the **unapplied** clones; cancel = delete unapplied clones. No per-(line, month)
  child table in V1.
- Validation: `to_month >= from_month`, `to_month` within the allowed month matrix
  (future months allowed to the same bound as single lines), locked months in the
  window → **409 `PAYROLL_MONTH_LOCKED`** listing them (matches the shipped
  ConflictException — the original 422 was a review-caught contract error; never
  partially stage).
- Cap interplay unchanged: negative recurring lines flow through the same 50% cap +
  roll-forward per month — no batching across months (recovery math stays monthly).
- Acknowledgment captured once at staging (covers all months) — matches the existing
  negative-line rule.

## Acceptance criteria

1. A 6-month recurring line appears in exactly 6 consecutive runs, one applied row
   each (journey leg with an N=3 window incl. a leaver month ending early).
2. Cancel stops future months only — already-applied rows intact (journey leg).
3. Re-run of a covered month is idempotent (no duplicate absorption).
4. `to_month` in a locked month → 409 `PAYROLL_MONTH_LOCKED` with the month named;
   window ending at a leaver's exit month stops cleanly (no post-exit absorption).
5. Summary recovery block reports per-line outstanding incl. remaining months.

## Test anchors

- 02 §7.6 (7) recurring-projection semantics (`test_salary_slip.py:1614` analog —
  recurring amounts join each covered cycle exactly once).
- Overlap/duplicate validation (`test_additional_salary.py:263` semantics).

## References

Frappe: additional_salary.py:331-397 selection (recurring window match), :43-49
(one-or-the-other enforcement), 02 §4.3.

## Risks / gotchas

- The leaver edge: a recurring line outliving the employee must stop at the exit-month
  run (final-run rules apply) — pin it, don't discover it in prod.
- Do not widen the recovery unique `(tenant, membership, month_raised)` semantics —
  recurring lines create one raised row per month or one row consumed monthly; pick
  one and prove with the existing reconciliation tests.
