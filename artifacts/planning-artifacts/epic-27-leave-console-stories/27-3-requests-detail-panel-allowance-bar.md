# 27-3 — Requests tab detail panel + allowance bar (web)

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-24) |
| Size | M (~1 day) |
| Layer | Web (fenzit-web) — extends the uncommitted requests build, **no BE** |
| Depends on | none (parallelizable with 27-2; state-disjoint) |
| Contract | design/requests-panel.jpg · design/DESIGN-MAP.md (drops) · `GET /attendance/leave/:employeeId/balances` (live) · `LeaveRequestView.employeeId` (leave.model.ts:52 — already on the wire) |

## Gap (evidence)

The uncommitted requests tab is a bare table with row actions. The design
(requests-panel.jpg) pairs the list with a **Request Details side panel**: who, when,
why, the employee's **allowance bar** (remaining balance for the requested type), the
day-by-day dates, and the decision buttons with full context. The allowance bar is the
only new wire call — and its endpoint already exists; the list rows already carry
`employeeId`, the web `LeaveRow` type just doesn't record it (companyApi.ts:94).

## Scope

1. **`LeaveRow.employeeId: string`** added to the FE type (BE already sends it — one
   line, unblocks everything below).
2. **Detail panel** (right side on desktop, matching the design; stacks below the
   table on narrow widths): employee name/code/avatar, status badge, From–To + part,
   "X of Y working days", the `dates[]` day-by-day line (state per day — the split
   view a revoke dialog talks about), reason, created date.
3. **Allowance bar**: for the panel's request, fetch
   `GET /attendance/leave/:employeeId/balances` and render the row for the request's
   leave type — remaining/entitled as a simple bar + "N of M days left". Which type a
   request is for: **verify what the wire carries before building** (the list view
   carries no leaveTypeId today — if absent, render the balance list generically: one
   line per type with remaining days; do NOT add a BE field for this — the generic
   list satisfies the design's intent without widening the API).
4. **Decisions move into the panel**: Approve / Reject / Revoke buttons in the panel
   footer reusing the existing `DecisionForm` (same dialogs, same fetcher contract).
   Row-level quick actions stay (already built — zero cost, and the design's mobile
   sibling uses row-level actions).
5. Panel opens on row click (and a visible "Details" affordance for a11y — rows are
   not naturally focusable); Escape/backdrop closes; selection survives the list
   refreshing after a decision (revalidate keeps the panel's request selected if still
   present, closes if gone).

## Out of scope

Coverage check ("1 other team member available in office" — dropped, DESIGN-MAP.md),
approval note (dropped), per-request chat/audit, editing requests, mobile.

## Technical approach

- Panel state = `useState` (selected request id) in `RequestsPanel`; the balances
  fetch happens when the panel mounts/switches — use the loader, not an effect: the
  selected id goes in the URL (`?tab=requests&status=…&cursor=…&selected=<id>`), the
  loader fetches page + balances for the selected id in parallel, and a closed panel is
  just no param. This keeps the repo's URL-owns-state idiom and the no-useEffect rule.
- Balances wire client: `fetchLeaveBalances(token, employeeId, signal)` in
  `leaveApi.ts`, typed from the BE view (per-type remaining — verify the exact response
  shape in leave-balance.service.ts before typing it).
- Reuse `JobSettingsDialog`-adjacent panel styling but as a persistent side panel
  (not a `<dialog>`) — new CSS Module, tokens only.
- After a decision the loader revalidates (action default) → the panel re-reads
  balances too (they changed — approved days consume).

## Acceptance criteria

1. Row click opens the panel with that request's full detail + balances bar; switching
   rows swaps the panel; the URL carries `selected=`.
2. Allowance bar shows real remaining days for the employee (contract test pins the
   balances response shape actually returned by the BE — source-verify first, the
   23-11 lesson).
3. Approve/Reject/Revoke work from the panel (same dialogs); after a done decision the
   list AND the panel refresh; a revoked-then-gone request closes the panel gracefully.
4. Panel is keyboard-reachable (Details button focusable, Escape closes, focus
   returns to the row — the 23-11 receipt-dialog-focus pattern).
5. Employee with zero balances / no balance rows: honest empty state ("No balance
   recorded for this type"), never a broken bar.

## Test anchors

- AdminLeavePage.test.tsx: `selected=` param drives the balances fetch (assert the
  URL), panel renders detail fields, decision-from-panel POST bodies (reason
  present/omitted), 409 stale-decision copy inside the panel context.

## References

design/requests-panel.jpg; uncommitted `AdminLeavePage.tsx` RequestsPanel +
`LeaveRequestActions.tsx`; BE `leave-balance.service.ts` (balances view — source-verify
the shape).

## Risks / gotchas

- **The list view carries no leaveTypeId** — the design's "Earned Leave (EL)" pill on a
  request row has no data source on the list wire. Pin the generic-balances fallback
  (scope 3) rather than widening the API (owner: keep it simple). If the owner later
  wants type pills on rows, that's a new story with its own BE line.
- Balances endpoint needs `leave.read_all`-adjacent permission for the owner — verify
  the controller's guard (it's the same file family as the list) before wiring.
- Avatar URLs are short-lived presigns — the panel must use the row's
  `employeeAvatarUrl` (already presigned per page), never refetch.

## Code review (BMAD thorough, 2026-11-24) — this card's share

Same review run as 27-2's block. This card: 8 patch · 1 defer · 3 rejected.

### Patched
- Pager addresses (Older ›, Start over) now drop `selected` — a selection
  belongs to one walk, so the panel can no longer silently close on the older
  page and then RE-OPEN when Start over returns (BH-7); new wire test pins the
  cursor-without-selected contract (VG-4/BH-7).
- `formData()` moved inside the action's try, after the auth check, with
  `intent` hoisted for the catch — a malformed body now degrades to the
  graceful error result instead of the page error boundary (ECH-1).
- Detail panel's Escape no longer closes the panel when the keypress
  originates inside an open decision dialog (`closest("dialog[open]")` guard)
  — Escape meant for the dialog stopped eating the panel too (ECH-3).
- Footer renders only for pending/approved rows — a decided row no longer
  draws the divider line under nothing (BH-10).
- Decision dialog form wired `aria-labelledby={formId}` — the id was on the
  h3 with nothing pointing at it (BH-12).
- Panel's From fact guards `part !== undefined` like the table does — no more
  latent "· undefined" (BH-17).
- LEAVE_PAGE_SIZE comment corrected: the pager is Older/Start-over, not a
  "Next/Back pair" (BH-6).

### Deferred
- Backdrop-click during an in-flight decision closes the dialog and hides the
  error. Self-recovering (the row keeps its old state; retry works), and the
  fix means restructuring who owns the dialog/busy state — not worth it now
  (ECH-2).

### Rejected
- Unknown-intent / empty-id results mislabel `kind` (BH-11): the paths are
  unreachable from the real forms and no leave consumer reads `kind` (only
  `state`/`message`) — the label is inert.
- Raw negative balances ("−2 of 12 days left") (BH-13): honest data; the bar
  already clamps; over-balance is a real configured state.
- Revalidate-after-approve assertion (VG-5): revalidation is React Router's
  default (commented in routes.tsx) — a test would pin the framework, not us.

### Tests added (VG-1, VG-3)
- Revoke wire test: confirm stays disabled until the required reason exists,
  then posts `{reason}` (VG-1).
- Balances 500 degrades to "The balance could not be loaded" with the request
  still shown (VG-3).
- The reason input's raw `font-size: 16px` (off the type scale) is now
  documented in the CSS — it is the iOS anti-zoom guard for the one console
  input likely to be typed on from a phone (BH-15).
