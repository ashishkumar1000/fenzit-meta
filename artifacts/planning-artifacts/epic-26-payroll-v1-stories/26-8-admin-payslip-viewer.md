# 26-8 — Admin payslip viewer (console)

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | S (~1–2 days) |
| Layer | Web (fenzit-web) — **no BE changes** |
| Depends on | none (API ships since 23-8) |
| Contract | 05 §6 WI-H · 03 §5, §10.F · 04 §screens |

## Gap (evidence)

The admin payslip API **ships and is unused by the console**: `GET /payroll/payslips`
(admin month roster) + the admin per-employee PDF POST have no web UI (03 §5, §10.F —
"API-only gap"). The owner can't view/download an employee's payslip from the console;
only employees see slips (mobile).

## Scope

1. New payslip roster view on the payroll console surface (likely a tab next to
   Runs/Audit): month picker → roster grid (employee, status, net, generated-at).
2. Per-employee PDF via the shipped admin POST → presigned download (one-request-per-
   LIST pdf read by payslipId — the 23-8 contract).
3. Status badges: locked / available / generating (PT429 dedupe surfaces as
   "generating, try shortly"). **Lock state comes from `GET /payroll/months/:month`
   fetched by the same loader** (the roster payload has no lock flag — verified
   2026-11-21); the runs tab's month card remains the lock *action* surface.
4. Honest empty states (Sally rules): no run that month, all-skipped month, queue
   paused (cross-link 26-14's pause state).

## Out of scope

Editing payslips from the console (never — snapshots are immutable), bulk PDF zip
downloads (polish), employee-facing web payslips (mobile owns that), monthly YTD
display (26-10/26-11).

## Technical approach

- Follow the 23-10/23-11 console idioms: URL-owns-state loaders (month in the URL),
  one intent-keyed action, native dialogs, summary rendered verbatim from the BE.
- The roster shape comes straight from `GET /payroll/payslips`; do not invent client-
  side aggregations the API doesn't return.
- Download UX: reuse the existing report-download affordances (presigned fetch +
  save) so the interaction matches the rest of the console.

## Acceptance criteria

1. Roster renders from the shipped API with zero BE changes (contract test in web
   pins the response shape).
2. Per-employee PDF downloads for a generated month; generating/PT429 states show
   honest copy and never look broken.
3. Month state lives in the URL (shareable/refreshable).
4. Locked months visually distinct from unlocked (the console already quotes the
   permanence copy on the runs card — same tone here).
5. Empty states per Sally rules; suite green (bun:test, web gates).

## Test anchors

- Web tests pin the API contract (03 §5 documents the shape — source-verify against
  fenzit-be, the 23-11 lesson: a lens found the web encoding a contract the BE never
  shipped).

## References

Frappe desk payslip list (04 §screens); our 23-8 API story (sprint-status 23-8 entry
documents GET surface + PDF POST semantics).

## Risks / gotchas

- The 23-8 API was never consumed by a UI — expect small contract surprises
  (pagination? id tiebreakers?); source-verify the controller before building, and if
  a genuine gap appears, it's a tiny BE follow-up, not web-side shoehorning.
- Keep it desktop-first; mobile app already covers employee self-service.
