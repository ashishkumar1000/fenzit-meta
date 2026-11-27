# 26-14 — Report-queue pause UI (console)

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | S (~0.5 day) |
| Layer | Web (fenzit-web) — **no BE changes** |
| Depends on | none (API ships since 23-8) |
| Contract | owner-approved quick-win (2026-11-21, promoted from the 23-8 ledger) · sprint-status 23-8 entry ("admin-panel pause UI = future FE story") · 03 §5 |

## Gap (evidence)

23-8 shipped the per-tenant report-queue pause API (report_queue_pauses: GET status /
POST pause 1–1440-or-forever / POST resume; `report.queue` permission; the worker
fences paused tenants in-SQL per tick) and explicitly ledgered "admin-panel pause UI =
future FE story" (sprint-status 23-8). The console can't pause/resume the queue; the
API is dark.

## Scope

1. Pause card on the payroll/reports console surface: current status (active pause
   with duration/forever + who/when, or "queue running").
2. Pause action: duration picker (1–1440 minutes presets + forever) with the plain-
   English consequence copy ("PDF/report generation for your company pauses; queued
   items wait, nothing is lost").
3. Resume action + state transition (banner swaps cleanly; focus restored — the
   23-11 receipt-dialog-focus pattern).
4. Permission: `report.queue` (admin) gates the card entirely; others never see it.
5. Banner on report surfaces while a pause is active ("generation paused — your
   request will complete when the queue resumes"), so a queued payslip doesn't look
   broken.

## Out of scope

Per-report-type pauses, queue-depth metrics dashboards, pause audit browsing (the
audit trail already records the mutations), mobile (admin-only surface).

## Technical approach

- URL-owns-state + one intent-keyed action per the 23-10/23-11 idioms; the pause/
  resume POSTs are idempotent intents with the shipped API's own validation.
- Source-verify the controller contracts before building (the 23-11 lesson — the web
  once encoded a contract the BE never shipped; three lenses caught it).
- The active-pause banner should derive from the same GET status call, polled or
  revalidated on navigation (React Router shouldRevalidate idiom — the attendance
  page contract).

## Acceptance criteria

1. Pause (timed + forever) / status / resume all reachable; every BE error code has
   matching inline copy (contract-pinned web tests).
2. `report.queue`-gated visibility; non-holder sees nothing (no dead buttons).
3. Active-pause banner appears on report surfaces and clears on resume.
4. Suite green; all static gates.

## Test anchors

- 23-8 API semantics (1–1440-or-forever bounds, paused-tenant fencing is worker-side —
  the UI only reflects state).

## References

23-8 sprint-status entry (the shipped surface); 03 §5 (pause UI listed as API-only
gap); Sally honest-empty-state rules.

## Risks / gotchas

- Forever-pauses deserve a scarier confirmation than timed ones (an owner who forgets
  a forever-pause blocks all payslip PDFs silently) — mirror the lock dialog's
  permanence-copy pattern.
- Don't build queue-depth analytics into the card; status + actions only.
