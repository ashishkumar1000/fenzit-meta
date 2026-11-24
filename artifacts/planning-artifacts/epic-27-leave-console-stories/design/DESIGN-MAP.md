# Epic 27 design map — Stitch project 470446784646785367 ("Two-Tab Screen UX Redesign")

Owner's Leave-section designs, downloaded 2026-11-24 via the Stitch MCP (owner-supplied
API key; key is a secret — never commit it). Eight screens; the four web ones are the
contract for this epic. The design's decorative filler ("Executive Pulse View", LeaveHub
branding, mock type names like Casual/Personal/PTO, EMP-1015 codes) is NOT contract.

| File | Screen | Story |
|---|---|---|
| `types-live.jpg` | Web **Types tab**, Earned Leave active. Master-detail: 4 summary cards on top (name, "12 days / year", mode chip, Click-to-Edit), rules editor below (Enable + off-warning, Paid, rate stepper w/ presets + "1 day/mo = 12 days/yr" hint, carry-forward, over-balance, one Save), right rail (quota breakdown + Upcoming time off). | 27-2 (rail's upcoming list → 27-4) |
| `types-turned-off.jpg` | Same tab with Earned Leave **disabled**: card shows "Turned Off", editor shows the red off-warning banner. | 27-2 |
| `requests-panel.jpg` | Web **Requests tab** with Request Details side panel: employee header, allowance bar (per-type remaining balances), dates, reason, coverage check, approval note, Approve/Decline. | 27-3 |
| `calendar-month-grid.jpg` | Web **Calendar tab**, month grid: day cells show who is out; month nav. | 27-4 |
| `calendar-timeline.jpg` | Same tab, timeline view: This Week / Next Week / Next Month groups, "Back in 3 days" relabels, Upcoming Holidays rail. | 27-4 (timeline = stretch) |
| `day-detail-modal.jpg` | Day drill-down modal from either calendar view: everyone out that day (avatar, EMP code, office, type pill, "Day 2 of 4 (Active Today)", Return Date, note), type chips, person search, footer "N of N approved". | 27-4 |
| `mobile-types.jpg` | Mobile Types tab — same fields as the web editor (matches the values-only PATCH 1:1). | mobile (deferred) |
| `mobile-requests.jpg` | Mobile Requests list for the approver. | mobile (deferred) |

## Dropped (owner-delegated 2026-11-24 — no data, schema change, or N+1 behind them)

- Team Capacity meter ("78% Safe") and "At least 85% of the team will be working" — forward-looking coverage math.
- Quota donut (Available/Used/Planned) + "144 days/yr pool across 12 team members" — team-wide balance aggregation; keep the simple per-type rates list instead.
- Approval note on approve — no storage field.
- "Up to 15 days cap" on carry-forward — BE toggle is boolean; no cap field.
- Coverage check in request detail ("1 other team member available in office").
- Per-status counts on chips (Pending (7)) — keyset pagination has no totals.
- Day-modal footer "approved by Beta Yela (Owner)" attribution — rows carry the creator, not the decider; show "All N are approved." instead.

## API decision (owner-approved 2026-11-24)

One BE change: **`from`/`to` date-range params on `GET /api/v1/attendance/leave`** (27-1).
Everything else is zero-BE: Types config = the existing values-only PATCH; the allowance
bar = existing `GET /leave/:employeeId/balances` (`employeeId` is already on every list
row — `leave.model.ts:52` — the web `LeaveRow` type just doesn't record it yet).
