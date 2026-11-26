# 27-4 — Calendar tab: month grid, day modal, upcoming rail (web)

| | |
|---|---|
| Status | done — SHIPPED 2026-11-24 (fenzit-web b35ecd1 Leave section + 51217dd Upcoming Leaves tab; review patches 4d24e1a; pushed to main) |
| Size | M–L (~1.5–2 days) — the epic's biggest slice |
| Layer | Web (fenzit-web) — new tab; consumes 27-1 |
| Depends on | **27-1 live** (the `from`/`to` params) |
| Contract | design/calendar-month-grid.jpg · design/calendar-timeline.jpg · design/day-detail-modal.jpg · design/DESIGN-MAP.md (drops) · 27-1's overlap-filter wire |

## Gap (evidence)

The design's third tab shows who is away and when: a month grid with day cells naming
who's out, a day drill-down modal with each person's detail, an "Upcoming time off"
rail, and an Upcoming Holidays rail. Nothing on the web answers "who's away next
week?" today; the data exists (approved leave + holidays) but needs 27-1's date filter
to read a bounded window honestly.

## Scope

1. **Third tab** "Calendar" (`?tab=calendar`): month view, month navigation (‹ Nov 2026
   ›, today button) — the month is URL state (`?tab=calendar&month=2026-11`), the
   loader derives `from` = month start, `to` = month end.
2. **Data read**: `GET /attendance/leave?status=approved&from=<start>&to=<end>&limit=50`
   — expand each request's `dates[]` into day cells client-side. A request wider than
   the month clips to the window (overlap semantics from 27-1 make this correct).
   Pending requests are NOT on the calendar (design shows approved only).
3. **Month grid**: 7-column grid, each day cell lists the people out (avatar + name,
   clipped with "+N more" when crowded); today highlighted; weekends/holidays tinted
   (holidays come from the existing `fetchHolidays` — same source the Holidays tab
   uses). Empty days render honest empty cells, no filler.
4. **Day drill-down modal** (day-detail-modal.jpg): click a day → everyone out that
   day as cards — avatar, name, EMP code, type-neutral status ("Approved"), duration
   line ("17–20 Nov · Day 2 of 4" when today falls inside; plain range otherwise),
   return date (next working day after `endDate`, skipping Sat/Sun — client-side),
   reason note. Person search = client-side filter over the day's cards. Type chips
   per day-list are DROPPED (rows carry no leave type — see 27-3's risk note); the
   modal's chips reduce to All only if trivial, otherwise omit.
5. **Upcoming rail** (shares the tab's right rail with 27-2's rates list): "Upcoming
   time off" — next ~10 upcoming approved days from today (a second 27-1 read,
   `from=today&to=+60d`, sorted by startDate), each "Name · 17–20 Nov"; "View
   Calendar" is a no-op link (already on the tab). Plus the **Upcoming Holidays rail**
   (calendar-timeline.jpg): next holidays from `fetchHolidays`.
6. **Timeline view** (calendar-timeline.jpg) = stretch: This Week / Next Week / Next
   Month groups reusing the same data. Build only if the grid + modal land green with
   time left; otherwise defer without ceremony.

## Out of scope

Team capacity / "78% Safe" meters (dropped), "approved by Beta Yela" attribution
(dropped — rows carry creator, not decider; footer reads "All N are approved."), drag/
click-to-approve from the calendar, month-dropdown filter (the grid's own nav is the
filter), mobile.

## Technical approach

- Loader extension in `leaveLoaders.ts`: `tab=calendar` branch reads `?month=` (validated
  `YYYY-MM`, else current month), fires the two 27-1 reads + holidays in parallel,
  returns `{ state: "ok", tab: "calendar", month, requests, holidays }`. Same
  failed/auth idiom as the other tabs.
- Client-side expansion: `dates[]` is already per-day with state — group by date into a
  `Map<date, LeaveRow[]>`; the modal reads that map. Pure functions, unit-testable, no
  effects.
- Grid is a new component pair (`LeaveCalendarGrid` + module.css); modal reuses the
  native `<dialog>` idiom (AddCustomerDialog pattern: backdrop click closes, remount via
  key). Day-cell "+N more" is CSS truncation + a count, not hidden DOM.
- File sizes: the grid + modal + rail are separate files from the start; nothing over
  ~300 lines.
- The rail slot: if 27-2 shipped first, reuse its rail container; if not, define it here
  and 27-2 adopts (either order works — the container is presentational).

## Acceptance criteria

1. Month nav changes the URL; the loader re-reads the window; cells show exactly the
   approved requests overlapping the month (journey leg incl. a request clipping both
   edges, and a span crossing the month boundary twice-rendered correctly).
2. Day modal lists the day's people with duration/day-N/return-date lines; search
   filters; escape/backdrop closes; focus returns.
3. Upcoming rail: next approved leaves from today (60-day window), holidays rail next
   up first; both honest when empty ("Nothing scheduled.").
4. 27-1 regression pair: with `from`/`to` omitted the calendar never renders; with
   them present the p95 stays well under the old N+1 incident's 17s (the read is one
   page + holidays — two statements).
5. Holidays tint + weekend tint render from real tenant data (the Beta Yela tenant has
   holidays — browser-verify leg).

## Test anchors

- AdminLeavePage.test.tsx calendar branch: month param → correct from/to query params
  asserted on the wire; expansion/clipping matrix; modal open/search/close; rail
  ordering; empty-month honest state.

## References

design/calendar-month-grid.jpg, design/calendar-timeline.jpg,
design/day-detail-modal.jpg; 27-1 card (the wire); existing `fetchHolidays` client +
Holidays tab (holiday source).

## Risks / gotchas

- **Page cap**: a month with >50 approved requests truncates silently — render the
  design's honest catch-all: if `hasMore`, show "and N more…" line in the overflow
  position (count unknown → "More requests exist — use Requests for the full list"),
  never a wrong complete-looking grid.
- Month state vs today: a stale URL month (user sits on the tab across midnight)
  re-resolves on the next navigation, not live — fine; don't add timers.
- The 60-day upcoming window is a product guess — pin the constant, name it, keep it
  one line to change.
- Timezone: "today" must be the tenant's today (the BE's dates are tenant-local ISO);
  the client has no tz context — derive "today" from the loader's server date if the
  wire carries one, else UTC-date is wrong for late-night IST owners. Source-verify
  what the BE list/holidays return before pinning (the module computes "today"
  server-side everywhere — follow its lead).

## Code review (BMAD thorough, 2026-11-24) — this card's share

Same review run as 27-2's block. This card: 5 patch · 1 defer · 3 rejected.

### Patched
- "Day N of M" now means TODAY: the number was computed from the clicked date
  while the line only showed when today fell inside the span, and the
  denominator was `totalDays` (calendar span) against a numerator counted in
  working dates. Now `dayNumberOf(person, today)` over `workingDays`, and a
  non-working today (weekend inside the span) shows just the span instead of
  a nonsense "Day 0" (BH-1).
- Grid roles dropped (`role="grid"`/`columnheader`/`gridcell`): the CSS
  layout has no row wrappers, so the roles promised arrow-key cell navigation
  the layout does not keep. Occupied days stay honest buttons (BH-2).
- Occupied day's accessible name now carries WHO is away ("2026-11-17: Asha V
  away", "+N more" beyond two) — a screen reader hears the cell's names, not
  just a count (BH-3).
- `monthCells` moved to leaveDateMath (exported, 2 new tests: Sunday-first no
  lead for 2026-11; Tuesday lead + 31 days for 2026-12; non-leap 28) — the
  grid's date math is now pinned like the rest of the module (BH-9).
- The calendar tab is `key`ed by the month in AdminLeavePage: a month change
  remounts the tab, so a day modal opened on browser-Back/Forward can no
  longer survive above a grid that no longer contains its day (ECH-4).

### Deferred
- Day-modal search hides per-card results but the "N people are away" hint
  keeps the total (BH-20): the total stays true, the "Nobody matches" line
  covers the miss case — polish, not a defect. (Filed with the defer bucket
  rather than rejected because the hint could read "N of M shown".)

### Rejected
- Upcoming rail "drops hasMore" (BH-5): the rail's own shown-count line
  ("More requests exist") already covers every case hasMore would — passing
  it through would be dead data.
- Holidays rail/tints "stop past the payload" (BH-14): the loader fetches the
  whole holidays list (the Nov browser pass showed New Year Jan 1) — the rail
  and tints are year-wide.
- Month "0000-01" hand-edited URL renders garbage without crashing, and
  Today recovers (ECH-7): garbage-in on an unreachable-via-UI address.
