# 26-13 — Monthly attendance sheet export

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | S (~0.5–1 day) |
| Layer | BE (fenzit-be) + web (fenzit-web) |
| Depends on | none (reports registry + day-status grid exist) |
| Contract | 05 §7 rows (promoted to V1 quick-win, owner 2026-11-21) · 03 §10.F ("attendance report exists — infra reusable") · 01 row 53 |

## Gap (evidence)

Attendance lives in the redesigned day-status grid but has **no month-export**; owners
close attendance before payroll (Frappe's documented flow, agent 1 row 53) and today
must eyeball the screen. The reports registry already holds a non-payroll attendance
report — the infra is proven reusable (03 §10.F).

## Scope

1. Reports-registry entry `attendance_sheet` (CSV first, XLSX if cheap): one row per
   employee, one column per day of the month. Day-status cells encode the **12 shared
   `STATUS_KEYS`** (src/common/day-status/keys.ts: `not_tracked, not_checked_in_yet,
   in_progress, weekly_off, holiday, worked_on_holiday, leave, half_day_leave,
   present, half_day, absent, checkout_missing`) — the original card list
   (present/absent/half/…) didn't match the contract and was corrected in review
   triage. The leave **type** renders via the leave join (not a status key);
   `half_day` vs `half_day_leave` render distinctly; days with **no status row**
   render as `unmarked` (a payroll-side concept — mapped per 26-5's
   `unmarked_days_as`, and shown as raw "no record" in the cell, labelled in the
   legend). Plus summary columns (payable days, LOP days, unpaid-leave days).
2. Same month matrix + day-status source the payroll engine consumes (the shared
   day-status grid) — export == what payroll will see.
3. LOP-relevant cells flagged (absent / unpaid-leave / half) so the owner can spot
   pay-impacting days at a glance.
4. Web: export button on the attendance/payroll surface (month picker, queued/ready
   states via report_requests). Minting follows 26-6's pinned route decision
   (payroll-side payroll.config-gated POST that plain-inserts into `report_requests`;
   status via `report.read`) — the generic `POST /reports` is `report.request`-gated
   and broader, so it can't carry the payroll.config gate.

## Out of scope

Editing attendance from the export (corrections happen in the grid pre-lock),
biometric/device reconciliation, auto-attendance settings, pivot-style multi-month
views.

## Technical approach

- Reuse the report worker path exactly (pure shape validateParams, tenant-scoped
  fetch, upload before ready stamp — 23-8 pattern).
- Batch the day-status fetch (the leave-list N+1 lesson: readPageSpanFacts batches
  statements — same shape here; one query per month-range, not per employee-day).
- Column header row = dates (1..31 with weekday initials); day-status codes match the
  shared keys (src/common/day-status/keys.ts) so the export is unambiguous.
- Scope = the same month window the run would use (payroll month, not calendar-first).

## Acceptance criteria

1. Export cell values == grid values for the same employee+month (spot-pinned legs;
   determinism is the whole point — the owner closes attendance against this file).
2. Summary columns reconcile with the engine's payable/LOP derivation for the month
   (or are labelled as raw day counts if intentionally pre-engine — decide + pin).
3. Batched fetch: query count independent of employee count (test or review-verified).
4. payroll.config-gated; queued for large tenants; PT429→429 preserved.
5. Month with a leaver/joiner: only employed days get statuses; outside-window days
   empty (not "unmarked").

## Test anchors

- Day-status key fidelity (src/common/day-status/keys.ts is the contract).
- The leave-list N+1 batch pattern (a11564c) as the performance anchor.

## References

Frappe: Monthly Attendance Sheet report (01 row 53); our own reports registry +
23-8 worker pattern; attendance-page redesign 2026-11-20 (grid is the source of
truth).

## Risks / gotchas

- **Unmarked vs absent semantics**: the export shows raw day statuses, while the
  engine's payable-days math applies the 26-5 `unmarked_days_as` setting — the summary
  columns must state which semantics they used, or the export will contradict the run
  (decide: show raw statuses + payable/LOP per current engine semantics, labelled).
- Feb cut-off >28 is refused by the calendar — the export for such a month should
  still exist (it's attendance, not payroll) unless the month matrix forbids it;
  align with the calendar validation, don't invent a new rule.
