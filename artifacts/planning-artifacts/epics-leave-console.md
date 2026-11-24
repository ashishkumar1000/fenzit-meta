# Epic 27 — Leave console: web per the Stitch designs

Registered 2026-11-24 (owner direction: check the Stitch Leave designs at project
470446784646785367, map them to the web console, "first do web and then go for
mobile", USE BMAD, don't overengineer, "make API simple … if required we can split
APIs"). The web Leave section (Types + Requests) already exists uncommitted in
fenzit-web from the pre-design build; this epic aligns it to the designs and adds
the Calendar tab. **Read before building:**

- `epic-27-leave-console-stories/design/DESIGN-MAP.md` — screen inventory + drops + API decision
- `epic-27-leave-console-stories/design/*.jpg` — the eight Stitch screens

## Mission

The owner's web Leave section matches the Stitch designs: a **Types** tab styled as
master-detail (summary cards → rules editor), a **Requests** tab with a detail side
panel (allowance bar from real balances), and a **Calendar** tab (month grid + day
drill-down + upcoming rail). One small BE addition (`from`/`to` on the owner leave
list) is approved; everything else rides existing endpoints. Mobile screens are
mapped but deferred — no cards until web ships.

## Decisions pinned at registration

- **API**: exactly one change — `from`/`to` overlap filter on `GET /attendance/leave`
  (27-1). No new endpoint, no counts endpoint, no schema change. Owner answered the
  AskUserQuestion 2026-11-24: "Add from/to params (Recommended)".
- **Drops** (owner-delegated, listed in DESIGN-MAP.md): team-capacity meter, team quota
  donut + pool number, approval note, carry-forward 15-day cap, coverage check,
  per-status chip counts, day-modal approver attribution.
- **Tabs**: Types / Requests / Calendar (`?tab=` idiom, same as Attendance).
- **Already built (uncommitted)**: routes/loader/action/wire-clients for Types +
  Requests, `LeaveTypeCard`, `LeaveRequestActions`, sidebar entry, error copy. The
  stories restyle/extend this — not greenfield.

## Sequencing

BE first (deploys first), then web stories — 27-2/27-3 are state-disjoint
(parallelizable per the multi-agent rule); 27-4 depends on 27-1 being live.

| Story | Layer | Size | Depends on |
|---|---|---|---|
| 27-1 `from`/`to` date-range filter on the owner leave list | BE (fenzit-be) | S | none — **build first** |
| 27-2 Types tab master-detail restyle | Web (fenzit-web) | M | none (27-1 not needed) |
| 27-3 Requests tab detail panel + allowance bar | Web (fenzit-web) | M | none (27-1 not needed) |
| 27-4 Calendar tab: month grid, day modal, upcoming rail | Web (fenzit-web) | M–L | 27-1 live |

## Out of epic (explicit)

Mobile screens (map exists; cards after web ships), per-status counts, team capacity/
coverage anything, approval notes, carry-forward cap, calendar timeline view beyond a
stretch goal in 27-4.
