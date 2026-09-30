# Spec — Story 19-6: Employee self-view UI (Frontend)

- **Story:** 19-6 (FR-26, UJ-5) — the tracked employee's own month at a glance: their month calendar (read-only day sheet), "Days worked: «n» so far" running total, month summary chips, period counts, upcoming holidays and leave history — all on their existing **Attendance tab**; plus the `history_only` past-data posture with the "Attendance tracking ended on {date}" note; plus the retirement of the dev Component lab (this story closes Epic 19).
- **Repos:** fenzo-app (the screens) + ONE SMALL additive fenzit-be change: `attendance_ended_on` on the access view + `attendanceEndedOn` on `GET /attendance/me/access` (D2 — the only wire source for the AC's `{date}`; verified: NO end-date exists anywhere on the wire today). **Cross-repo order: fenzit-be merges/deploys FIRST, then fenzo-app** (same ladder as 19-5; the FE is null-safe without it, so the order is contract hygiene, not load-bearing).
- **Baseline:** fenzo-app at the 19-5a commit (`2f93ae8`); fenzit-be at `6d2f0fa`. The me/monthly `today` echo shipped in **`aa1b6c1`** (the 19-5 BE prereq, an ancestor of HEAD — verified; `a3c8aa8` closed Epic 19 BE and is also an ancestor).
- **Status:** draft → adversarial review (2 lenses) + UX design pass → **step-03 triage (§9: 22 findings → all dispositioned) → FROZEN for build.**
- **Sources:** epics-attendance-leave.md §Story 19.6 (ACs quoted where they bind); prd.md FR-26 ("A Tracked employee sees their own monthly calendar (Day status per date, flags), today's Check-in/Check-out state, month summary (same fields as FR-25), Weekly offs, upcoming Holidays and leave history… The Employee can only ever see their own data (enforced server-side)"); UJ-5 ("Priya opens My Attendance and sees this month's calendar with a status for each day, their weekly offs, upcoming holidays, their Leave requests with status (Pending / Approved / Rejected / Revoked with reason / Cancelled), and 'Days worked: 14.5 so far'"); FR-11 (totals parity — structural: ONE aggregation function on the BE); spec-19-1-to-19-3 §D6 (the me/monthly wire); the `useMonthStatuses` docblock (pre-committed: "19-5/19-6 embed it… the me path's 403 ATTENDANCE_NOT_TRACKED is deliberately this same ordinary state"); the `RealMonthPane` docblock (pre-committed: "19-6's self view embeds the same pane me-scoped… the dev Component-lab screen… retires with 19-6"); the `AttendanceTabScreen` docblock (15-10: "history_only → ended banner only… records surfaces are Epics 18/19" — this story fulfils that promise).
- **Out of scope:** any correction WRITE for employees (the day sheet is read-only — `canCorrectDay` is owner-scope-gated AND the sheet gets no write plumbing); owner surfaces (19-4/19-5 untouched); reminders (19-1, shipped); the 17-x leave surfaces beyond re-hosting `LeaveHistorySection` for `history_only`; notification deep-links; no new owner-side views.

## 1. Fix-placement analysis (per the root-CLAUDE.md rule)

| Concern | Layer | Why |
|---|---|---|
| The history_only end date (`{date}` in the AC's note) | **BE** (additive: view column + `me/access` field, D2) | The date does not exist on ANY wire surface today (verified: view definition + `toAccessStateResponse` — history_only is inferred from past enrolment periods, `max(upper(valid))`, never selected). Root cause is a wire gap; the FE must not fake or guess a date. |
| Own-month summary, upcoming holidays | **BE** (already shipped, 19-3 `GET /attendance/me/monthly`, echo via aa1b6c1) | FR-11 totals parity is structural (ONE aggregation with the owner route); the FE never re-sums. |
| Own day statuses (the calendar grid) | **BE** (already shipped, 18-3 `GET /attendance/me/day-statuses`) — FE embeds via `useMonthStatuses` `{kind:'me'}` | Server-side own-data-only (FR-26's consequence; the JWT identity is the only key). |
| Self-view layout, chips, so-far total, holidays list | **fenzo-app** | Presentation over wire rows; `summaryChips`/`formatCredit` reused verbatim (one chip implementation app-wide). |
| `history_only` note, past-only posture, leave-history re-host | **fenzo-app** (arrangement) over the BE date (D2) | The copy renders what the wire carries; the posture is the access store's existing state machine extended by one branch. |

## 2. Design decisions (locked before implementation)

**D1 — The surface is the Attendance tab, extended — not a new route.** UJ-5: "Priya opens My Attendance and sees…" — ONE surface. `AttendanceTabScreen` gains a **"My month"** section (`AttendanceMyMonth`), rendered INSIDE each posture branch (never hoisted out of the ternary — the active/history_only flip then remounts the section and re-runs its bootstrap; the › bound disables forward travel only and never snaps the month back; triage #7):

- **active:** `[Today (existing)] → Summary (existing) → My month (NEW) → Leave (existing)`. Do not move the existing sections (purely additive diff; existing pins extend). The tab reads: NOW → YOUR SETUP → YOUR MONTH → YOUR REQUESTS.
- **upcoming:** UNCHANGED — no My month at all (**UX ruling on Q1:** "absent, not disabled" is the state's doctrine; the wire would 200 an all-zero summary whose first chip is a false "0 worked" and whose calendar is an all-neutral grid reading as "counted, worked nothing"; D8's zero-fetch saving matters on the target device). Verified: me/monthly's 403 is none-only (`monthly.ts:166-168`), so hiding is a product choice, not a wire constraint.
- **history_only:** `[ended note (D6)] → My month (NEW) → Leave section (existing SectionHead + history, Apply row absent)` — replacing today's bare ended banner ("records surfaces are Epics 18/19", 15-10 — this story fulfils that).

No new route; nothing on the owner stack changes.

**D2 — BE additive: `attendance_ended_on` (the one BE change).** The view gains a final column, **gated to history_only** (triage F1: ungated, a disable→re-enrol employee would carry a stale "ended" date while active — the view's own CASE precedence is the gate):

```sql
CASE WHEN cur.period_start IS NULL AND nx.next_start IS NULL THEN
  (SELECT (max(upper(e.valid)) - 1)
     FROM attendance_enrolments e
    WHERE e.employee_id = u.id
      AND upper(e.valid) <= attendance_today(u.tenant_id)
      AND upper(e.valid) < 'infinity'::date)
ELSE NULL END AS attendance_ended_on
```

— the LAST TRACKED DAY (upper is exclusive). Types verified: `attendance_enrolments.valid` is **daterange** (`20260927000007:50`), `upper()` → date, `date - 1` → date, `attendance_today()` → date (`20260926000003:22-23`); `'infinity'::date` (the type-clean form — triage F3). Migration `20260930000001_attendance_access_ended_on.sql` (name verified free): `CREATE OR REPLACE VIEW public.attendance_access_state WITH (security_invoker = true)` **and re-assert the grants** (`REVOKE ALL … GRANT SELECT … TO service_role`) — the house pattern `20260928000001:29-30,111-113` (create-or-replace does not re-grant). Testing ladder: MCP-apply → local probe → push → production probe. `MeAttendanceService.getAccess` maps it as **`attendanceEndedOn: string | null`** (`YYYY-MM-DD`), after `attendanceStartDate`. **Deliberately NOT added to the `/users/me` attendance mirror** (19-5a): the mirror is the tab-gating vocabulary (4 frozen fields), owners are never history_only, and the gate never reads an end date. FE `attendanceMe.ts`: `AttendanceAccess` gains `attendanceEndedOn: string | null`; `normalizeAccess` maps a missing field to `null` (an older BE degrades to the dateless note — D6). With the CASE gate, `attendanceEndedOn` is null in every state except history_only (the D2 pins below are now true invariants). Tests: `me-attendance.service.spec` (history_only fixture → the date; active AND upcoming → null; no-past-rows history_only → null), `test/attendance.e2e-spec.ts` me/access `toMatchObject` pin gains the key (verified `:1452-1469`), `docs/api-contracts.md` me/access row + a view-semantics note.

**D3 — FE data: `fetchMyMonthly` + `useMyMonthly`, clamped by the PANE's echo (the P1 fix).** `src/services/resources/attendanceMonthly.ts` gains:
- `MeMonthlyData { from, to, today: string; summary: MonthlyEmployeeSummary; weeklyOffs: number[]; upcomingHolidays: { holidayDate, holidayName }[] }` — wire verbatim.
- `fetchMyMonthly(from, to)` → `GET /attendance/me/monthly?from=&to=` (params object, encoded once; read — no key).
- A fail-closed normalizer extracting the SHARED summary validator from `fetchMonthly`'s (one implementation: nine keys, integer/decimal rules verbatim from 19-5 D3); `today` REQUIRED + regex-checked; `weeklyOffs` sorted ints 1..7; `upcomingHolidays` rows `{holidayDate: YYYY-MM-DD, holidayName: non-empty}`. Unknown shape throws (whole fetch rejects). `me/monthly` is identity-scoped (NO employeeId param — the JWT is the key).
- **`useMyMonthly({ yearMonth, today })` — `today` is the PANE'S REPORTED ECHO (`RealMonthReport.today` from me/day-statuses), the section's ONE canonical clock (triage P1+P2):** me/day-statuses has NO future-to 422 (span ≤ 62 only — verified `day-statuses.controller.ts:47`), so its echo ALWAYS lands; me/monthly 422s on `to > tenant-today` (`monthly.ts:180-182`), so the hook NEVER fetches a window until `today != null`, then always `monthlyWindow(yearMonth, today)`. The draft's "plain-range bootstrap, 422 is the honest posture, symmetrical to 19-5" is DELETED (the P1: 19-5 seeds LAST month — no clamp needed — and its current month is reachable only through the echo-gated ›; a current-month plain-range fetch fails ~29 days out of 30 and its Retry re-derives the identical 422 — no echo ever lands). While `today == null` the hook idles in its loading posture (the pane's spinner is already on screen; the pane Retry→success supplies the echo). Seq-guarded latest-wins (the useMonthStatuses shape); **a `yearMonth` change runs the runFetch posture — data CLEARED, loading true, error cleared (triage #4: otherwise September's chips can paint under October's title)**; the silent in-place swap is the focus/AppState refetch ONLY: `useFocusEffect` + `AppState`-active both trigger it (triage #2 — parity with `useAttendanceSummary`'s midnight rationale and the pane's own AppState refresh). The hook's own response echo is recorded on the data but is NOT the section clock (see D5).

**D4 — `RealMonthPane` widens to me scope (the pre-committed patch).** `employeeId?: string` — ABSENT → `useMonthStatuses({ scope: { kind: 'me' }, yearMonth })`; present → today's owner behaviour byte-for-byte. `RealMonthReport` unchanged. Docblock rewritten: the pane is fully production (two hosts); the lab sentence deleted with the lab (D7). No other pane edits.

**D5 — The "My month" section (`AttendanceMyMonth.tsx`).** `SectionHead "My month"`, then `gap: spacing.s3` (the Summary wrap's rhythm; section-to-section stays the tab's `s4`), internal order (UX ruling): calendar → so-far line → chips line → meta line → holidays block.
- **The calendar:** `RealMonthPane` me-scoped (no `employeeId`), FULL height verbatim (cells are aspect-locked; a reduced variant would mint new visual language; UX ruling). The host owns `yearMonth` + `onShiftMonth` + the sheet wiring. **Month bootstrap (the 19-5 idiom, faithful — triage #5/#6):** the seed is the DEVICE month as declared navigation scaffolding (which month to LOOK at — never a fetch boundary); when the canonical echo first lands, the displayed month corrects ONCE toward `today.slice(0,7)` — **in the history_only posture the target is `min(todayMonth, attendanceEndedOn?.slice(0,7) ?? todayMonth)` (triage #6: an employee ended in August opens on their last real month, not an empty September; with a null date the today-open is unavoidable and accepted)** — and the correction follow-up is a PARAMETER load (the section's loading posture, never a silent swap: the month label changes under it), **re-arms once on its failure** (the 19-5 `useMonthlyData` ruling), and "navigated" means ‹/› presses ONLY (a day-sheet tap never stands the correction down). FETCH windows are always `monthlyWindow(yearMonth, canonicalToday)` (D3 — no plain-range fetch exists in this story).
- **› bound:** active — `canonicalToday == null || yearMonth === canonicalToday.slice(0,7)`; history_only — `canonicalToday == null || yearMonth >= (attendanceEndedOn ?? canonicalToday).slice(0,7)` (stops forward travel; never snaps back — D1). ‹ unbounded past.
- **The running total (UJ-5 literal):** when `yearMonth === canonicalToday.slice(0,7)` and the summary is loaded, one Text **"Days worked: «formatCredit(daysWorked)» so far"** (`typography.bodyStrong`/`textStrong`), rendered ABOVE the chips (UX ruling: headline + breakdown, not stutter — the chip keeps the 19-5 anchor role). Past months, in-flight and failed: no line (never a stale month's number under a new label).
- **The chips line:** `summaryChips(data.summary)` — the 19-5 atomic-chip row VERBATIM (colour families per the D4 map; worked anchor always first, zero is an answer; zero-suppressed otherwise). No me-specific suffix (UX Q2: the shared builder must never become month-state-dependent).
- **The meta line (counts only — UX copy ruling AMENDED):** `«n» weekly off«s» · «n» holiday«s» · «n» worked on holiday`, zero-suppressed, the whole line OMITTED when all three are zero (the captionSegments empty-omit precedent). The draft's `Weekly offs: «Sun, Mon»` config segment is DELETED (three sightings of "weekly off" on one screen — Summary already carries the config row; `formatWeeklyOffs` stays the Summary's). To keep "one implementation" structurally true (triage: `captionSegments` needs an `EmployeeMonthlyRow`), monthlyModel gains an exported `summaryMetaSegments(summary): string[]` (the three count segments, sharing the module's `plural` + `formatCredit`); the owner's `captionSegments` refactors to `[row.officeName?, …summaryMetaSegments(row.summary)]` — owner output byte-identical (pinned by the existing monthlyModel tests).
- **Upcoming holidays:** a block under the bare **`Eyebrow` "Upcoming holidays"** (the divider-less list-section header idiom, `accessibilityRole="header"`); rows `«holidayName» · «12 Oct»` at `gap: spacing.s2`, each Text carrying `accessibilityLabel="«Holiday name», «12 Oct»"` (commas — TalkBack never reads the dot). `[]` → the block is OMITTED (honest absence). **ACTIVE ONLY — hidden in history_only (UX Q3 OVERTURNS the draft):** the history_only grammar is subtraction in service of "your record is closed"; a forward-ticking list is its one contradiction. The short date is a tiny string-surgery helper colocated in monthlyModel (`«d MMM»` reusing the ONE MONTH_NAMES table — no Date in device zone; the customers-local formatter is Date-based, not reused).
- **The day sheet:** `DayDetailSheet` with `scope={{ kind: 'me' }}`, `readOnly`, NO `onCorrect`/`onCorrected` (verified: `canEnter = !readOnly && onCorrect != null && canCorrectDay(...)` and `canCorrectDay` independently returns false for me scope — the entry is doubly dead). CorrectionHistory works me-scoped verbatim (`fetchCorrections` routes `/attendance/me/corrections`, 18-2). Loading-month picks ignored (`report?.loading`). No focusDate deep-link.
- **Error/loading postures (per-surface):** the pane renders its own spinner + InlineError/Retry verbatim; the summary block renders a small quiet posture — loading = nothing (the pane's spinner covers the section's first paint), failure = `InlineError "Couldn't load your month summary. Check your connection and try again."` + a secondary `Retry` whose `accessibilityLabel="Retry month summary"` (triage #9: two stacked "Retry" buttons must be distinguishable). No Skeleton block (UX Q4 ruling: the Skeleton is row-shaped for list rows; the tab's idiom for this shape is the spinner + InlineError — 19-5's UX-DR5 clause is satisfied by reusing the pane itself; the Skeleton docblock note in D7).

**D6 — The history_only posture.** The ended banner becomes the persistent note: headline **"Attendance tracking ended on {formatLongDate(attendanceEndedOn)}"** (the existing `formatLongDate` en-IN idiom — the SAME construction as "Attendance starts on …"; no second long-date formatter is minted), body unchanged ("You can no longer check in or out, and nothing new is being recorded."). Null date (older BE): headline falls back to **"Attendance tracking has ended"** (15-10 copy). "Past data only": Today, the check-in control, the Apply row and the upcoming banner are ABSENT (absent, not disabled); `LeaveHistorySection` renders below My month (fetches on mount regardless of access state — verified; its detail sheet is already read-only); the bootstrap opens on the ended month (D5); upcoming holidays hidden (D5); the meta/chips render their past truth (FR-28's class of employee, visible to themselves).

**D7 — Component lab RETIRED (the closer).** The full deletion+sweep surface (triage F2/F7 — the draft's "no test imports the lab" was FALSE):
1. Delete `ComponentLabScreen.tsx`.
2. Remove the `ComponentLab` route (`types.ts:253`) + the `require()` registration (`RootNavigator.tsx:191-196`).
3. Remove the hub tile + `FlaskConical` import (`AttendanceHomeScreen.tsx:132-142,23`).
4. **`AttendanceHomeScreen.test.tsx:203-209` — DELETE the "tapping the dev row navigates to ComponentLab" case** and shrink the exact press-set pin (§5.6).
5. Docblock sweep: `RealMonthPane` (lab sentence), `DayDetailSheet` (the proof-pane sentence — `readOnly` STAYS, it is now the self view's production posture), `MonthCalendar` (the Epic-19 host sentence names both real hosts), `monthlyModel` ("extracted verbatim from ComponentLabScreen" → name the surviving home), `dayStatusVisual.ts:6` + `dayStatusVisual.test.ts:6` ("the ComponentLab's proof month"), and **`Skeleton.tsx:10-12`** ("the monthly view and the self view (19-5/19-6) reuse it" → the self view reuses the DS loading vocabulary via the pane/spinner postures; no row-shaped stand-in exists in a tab-embedded block).
6. **Retire `scripts/verify-no-component-lab.js` + its `package.json:13` step** (the release tripwire guarded a lab that now does not exist; a vestigial guard with false instructions is dead weight).

**D8 — Screen states, loading budget & accepted staleness.** The tab gains TWO fetches per shown month (`me/day-statuses` via the pane + `me/monthly` via the hook, the latter gated on the former's echo) and nothing else per focus beyond the silent refetches (access store's min-gap; summary in-place; pane AppState; hook focus+AppState). `upcoming`: zero new fetches (D1). Accepted staleness (recorded per triage #2): an employee who foregrounds the app across midnight WITHOUT backgrounding it and WITHOUT a tab switch keeps yesterday's cell/so-far/bound until the next fetch — the useMonthStatuses doctrine, extended to this permanently-mounted surface consciously. Accepted height-jump (triage #9): on month switches the calendar collapses to the pane spinner and re-grows (the map clears); the Leave section below moves — the 19-5 row-Skeleton solution was for LIST rows; here the UX ruling keeps the pane's own posture (Q4). No offline-specific branch (read screens fail honestly).

**D9 — Accessibility.** The summary block (so-far line + chips + meta) is ONE accessibility element with ONE assembled comma label, children hidden (the `MonthlyEmployeeRow` recipe transposed to a static group — UX ruling; per-line labels would announce the worked number twice): current month = `Days worked: 14.5 so far, 2 half days, 1 late, 1 leave, 1 absent, 2 missing checkouts, 3 weekly offs, 1 holiday` (the sentence carries the number — the worked chip is omitted FROM THE LABEL, not the screen; remaining chips + meta segments join with commas); past month = chips (worked anchor first) + meta segments joined ", "; loading/failed = no element (the InlineError speaks via `accessibilityRole="alert"`). `SectionHead` keeps its header role; holiday rows carry the comma labels (D5); the ended note stays two Texts with `accessibilityRole="header"` on the headline; the summary Retry is labelled (D5); chips stay self-labelling (never colour alone). Assembled strings pinned in tests.

## 3. Copy table (all user-visible strings; simple English, house punctuation)

| String | Where |
|---|---|
| My month | the new section head |
| Days worked: «n» so far (e.g. "Days worked: 14.5 so far") | running-total line, current month only (UJ-5 literal) |
| «n» worked / «n» half day«s» / «n» late / «n» leave / «n» absent / «n» missing checkout«s» | chips (19-5 verbatim — one implementation) |
| «n» weekly off«s» · «n» holiday«s» · «n» worked on holiday | meta line (counts only; line omitted when all zero) |
| Upcoming holidays | holidays block Eyebrow (ACTIVE posture only) |
| «Holiday name» · «12 Oct» (a11y: "«Holiday name», «12 Oct»") | one holiday row |
| Attendance tracking ended on «Sat, 12 Sept, 2026» | history_only note headline (formatLongDate of the wire date) |
| Attendance tracking has ended | history_only note headline (date null — older BE) |
| You can no longer check in or out, and nothing new is being recorded. | note body (15-10 copy unchanged) |
| Couldn't load your month summary. Check your connection and try again. | me/monthly failure line (never err.message) |
| Retry (a11y: "Retry month summary") | the summary block's retry button |
| «month» «year» / Previous month / Next month | pane furniture (shared strings) |

## 4. Code layout (files ≤ 300 lines, house structure)

```
fenzit-be (additive, deploys FIRST)
  supabase/migrations/20260930000001_attendance_access_ended_on.sql  # view (security_invoker re-asserted
                                                                     #   + grants re-asserted) + attendance_ended_on
  src/attendance/me-attendance.service.ts        # + attendanceEndedOn mapping (+ docblock)
  src/attendance/me-attendance.service.spec.ts   # history_only → date; active/upcoming → null; no-past → null
  test/attendance.e2e-spec.ts                    # me/access toMatchObject pin gains attendanceEndedOn
  docs/api-contracts.md                          # me/access row + view-semantics note
fenzo-app
  src/services/resources/attendanceMe.ts         # AttendanceAccess + attendanceEndedOn; normalizeAccess null-safe
  src/services/resources/attendanceMonthly.ts    # MeMonthlyData + fetchMyMonthly + shared summary validator (+ test)
  src/features/attendance/monthly/monthlyModel.ts # + summaryMetaSegments (exported; captionSegments refactored onto it,
                                                  #   output byte-identical) + the «d MMM» holiday-date helper
  src/features/attendance/monthly/monthlyModel.test.ts   # new pins + the byte-identical owner-caption pins
  src/features/attendance/me/
    AttendanceMyMonth.tsx                        # D5 section (calendar embed + summary block + sheet)
    AttendanceMyMonth.test.tsx                   # NEW
    useMyMonthly.ts                              # D3 hook (echo-gated, seq-guarded, focus+AppState silent refresh)
    useMyMonthly.test.tsx                        # NEW
    AttendanceTabScreen.tsx                      # D1/D6 wiring (per-branch mounting; history_only re-host)
    AttendanceTabScreen.test.tsx                 # posture + FLIP pins extended
  src/features/attendance/calendar/
    RealMonthPane.tsx                            # D4 employeeId optional → me scope; docblock
    DayDetailSheet.tsx                           # docblock sweep only (readOnly is production now)
    dayStatusVisual.ts / dayStatusVisual.test.ts # docblock sweep only
  src/components/ui/Skeleton.tsx                 # docblock sweep only (D7.5)
  src/features/attendance/home/
    AttendanceHomeScreen.tsx                     # lab tile REMOVED (D7)
    AttendanceHomeScreen.test.tsx                # lab case DELETED + press-set pin shrunk (D7.4)
  src/navigation/types.ts                        # ComponentLab route REMOVED
  src/navigation/RootNavigator.tsx               # lab registration REMOVED
  scripts/verify-no-component-lab.js             # DELETED (D7.6) + package.json step removed
  (DELETED) src/features/attendance/calendar/ComponentLabScreen.tsx
```

## 5. Test plan (jest/RTR, the house idioms)

1. `attendanceMonthly.test.ts`: `fetchMyMonthly` route + params (from/to only — NO employeeId param may exist); happy shape incl. empty weeklyOffs/holidays; fail-closed throws (bad today, non-1..7 weekday, non-object holiday rows, empty holidayName, the shared summary violations); the shared validator is the SAME function the owner path uses (pin the import).
2. `useMyMonthly.test.tsx`: NO fetch while `today == null` (the echo gate — the P1 regression pin); first fetch once today lands, window = `monthlyWindow` (clamped); `yearMonth` change CLEARS data + loading (triage #4); seq-guard older-resolves-late drops; focus + AppState-active silent in-place refresh (no clearing); error → Retry refires with the SAME clamped window.
3. `AttendanceMyMonth.test.tsx`: SectionHead; me-scoped pane embed (employeeId prop ABSENCE pinned); so-far line ONLY when `yearMonth === canonicalToday.slice(0,7)` AND loaded, `formatCredit` decimal ("14.5"), rendered above the chips, absent for past months/loading/failed; chips always-first worked anchor; meta line counts-only + omitted-when-all-zero (the draft's "No weekly offs" segment pin is DELETED — triage); holidays block active-only (history_only ABSENCE pinned — Q3), omitted on `[]`, row text + comma a11y label; sheet wiring `readOnly` + `scope.kind === 'me'` + NO onCorrect; pick suppressed while loading; › bounds BOTH postures (active bound Pinned — the pane's `nextDisabled` defaults false, a forgotten prop is an unbounded future month, triage #11d; history_only bound at the ended month + the null-date today fallback); bootstrap: history_only seeds/opens the ended month; correction follow-up is a parameter load and re-arms once on failure; "navigated" = ‹/› only; the grouped a11y label (worked chip omitted from the label in the current month; the exact comma string pinned).
4. `AttendanceTabScreen.test.tsx`: active → My month between Summary and Leave; upcoming → NO My month and no new fetches; history_only → dated headline (and the dateless fallback), NO Today, NO Apply row, LeaveHistorySection PRESENT, My month present; **a FLIP pin: active→history_only remounts the section (fresh bootstrap), history_only→active likewise** (triage #7/#11c); active→none still escapes to Today (existing pin survives).
5. `RealMonthPane`: me-scope passthrough (employeeId omitted → the hook receives `{kind:'me'}`); the owner pin survives unchanged.
6. `AttendanceHomeScreen.test.tsx`: the lab case is GONE; the exact press-set pin shrinks (the lab tile leaves the closed-set).
7. BE: the three `me-attendance.service.spec` endedOn pins; the e2e `toMatchObject` pin gains the key (additive — verified safe); the view migration's grants re-assertion is pinned by the MCP-apply probe (the ladder), not a unit test.

## 6. Device walkthrough record (2026-10-01, EXECUTED — Pixel 6 1C301FDF6002ZB, production BE post-deploy 8f791a1, Metro dev JS)

Every flow PASSED against production truth with Supabase-MCP DB verification at each step; the device clock (03:00–03:30 IST, Oct 1) matched the tenant clock throughout.

**Active posture (Arya, +91 1234576890, office Hero wala):**
- Tab order verified: Today card (Check in, "Hero wala · 9:00 AM – 4:00 PM") → Summary (Office/Timings/Late cut-off/Weekly offs Sun) → **MY MONTH** → Leave (Apply + history).
- October 2026 calendar: today ringed, approved-leave glyphs on the 1st–2nd (the 1–2 Oct approved request), the 8th's half-day leave, the 28th's leave, Sundays as weekly offs — all matching `leave_requests` + the engine's records.
- **"Days worked: 0 so far"** + chips **"0 worked · 1 leave"** — the clamped summary window (to = today = Oct 1) counts only the 1st: leave=1 ✓, meta line correctly OMITTED (all zero on day 1). "Holi · 4 Oct" from upcomingHolidays ✓.
- Day sheet on 2 Oct (leave): Leave badge, Office "Hero wala", **NO "Correct day" anywhere** (readOnly + no plumbing). Day sheet on 30 Sep (worked): **Half day** badge, **Early · 120m** + **Corrected** flags, Check-in 8:57 AM / Check-out 2:00 PM, Worked 5 h 03 m (8:57→14:00 exact), note "owner added checkout" — all DB-faithful (`attendance_records` 03:27:42Z + the null-status override).
- Month paging: ‹ to September (the 29th ABSENT — the 18-4 override, DB-verified `attendance_day_overrides` 2026-09-29 absent; the 30th's checkout-missing clock glyph; chips "0.5 worked · 1 half day · 1 absent") and further to August (all-neutral honest empty month, so-far line absent, "0 worked" anchor persists). **› disabled at the current month** (uiautomator `enabled=false`), enabled one month earlier.

**history_only posture (Suresh a644027a, office Yuka):** enrolment+assignment clipped to [Sep 30, Oct 1) via MCP (the disable path's own clip; the coverage guard demanded both). **"Attendance tracking ended on Wed, 30 Sept, 2026"** — the DATED headline rendering the new wire date. No Today card, no Summary, no Apply row; My month present; **no Upcoming-holidays block** (Q3); leave history renders (5–7 Oct · Revoked). › disabled at September (the ended-month bound), enabled in August. Day sheet on the 29th: Absent badge, Office "Yuka" (per-date assignment truth), read-only. September chips "0 worked · 2 absent" matched the empty `attendance_records`. (Observed engine note, not a defect: the 28th renders neutral — the enable-day leniency; the owner's monthly view shows the same by FR-11's one-engine parity.)
- **Live flip verified:** restoring the enrolment + re-focusing the tab flipped Suresh back to active (Check-in card returned, ended note gone, My month re-bootstrapped on October — the remount doctrine).

**DEVICE-FOUND BUG (BUG-1 = R9 reclassified + FIXED):** on a FRESH login the history_only bootstrap opened **October** (today's empty month) instead of the ended month — the profile seed carries `historyOnly=true` but `attendanceEndedOn=null` (the /users/me mirror is gate-vocabulary only, D2), so the one-shot correction burned on the pane's echo before me/access delivered the date. The deferred-R9 risk is the COMMON fresh-login path, not a narrow race. **Fix (FE — the section owns its bootstrap):** an `attendanceEndedOn` TRANSITION re-opens the one shot while un-navigated (the watcher resets the burn refs; the correction effect's deps gained the date; navigated users stand it down). Regression-pinned both ways (burn re-corrects; navigated stands down). **Live-verified:** fresh app restart as clipped Suresh → October+spinner (the parameter load) → **September, chips "0 worked · 2 absent"**. Honest restore applied after (Suresh active again, ended_on null — view-verified).

**Post-fix verification:** fenzo-app `bun run test` → **223 suites / 2767 tests, all passing** (+2 R9 pins); `bunx tsc --noEmit` → clean. One full-run flake episode (home-screen suite under stale jest workers) passed 23/23 isolated and the clean serial rerun was green — the reviewers' environmental class, not code.

**Not device-probed, recorded:** the check-in bridge (R1) live-fire — today (Oct 1) is an APPROVED-LEAVE day for Arya (check-in would fire the 17-8 leave-cancel dialog and mutate real leave state at 3 AM; declined), and the bridge is unit-pinned (3 assertions). The owner drill-down's Correct entry was untouched and its 19-5 walkthrough stands.

## 7. Open questions — DISPOSITIONED by the review pass (2026-09-30)

- **Q1 upcoming → HIDE My month (confirmed the draft).** "Absent, not disabled" doctrine; a 200 all-zero render reads as "counted, worked nothing" (first chip "0 worked", all-neutral grid); saves the fetches.
- **Q2 running total → BOTH the line and the chip (confirmed).** The line is the AC's named element; the chip keeps the shared anchor; bodyStrong/captionStrong reads as headline + breakdown. Line ABOVE chips.
- **Q3 upcoming holidays for history_only → HIDE (OVERTURNS the draft).** The posture's grammar is subtraction; a forward-ticking list contradicts "your record is closed". Active keeps the block.
- **Q4 summary first-load → pane spinner + per-surface quiet errors (confirmed; no Skeleton).** The Skeleton is row-shaped for list rows; the tab's idiom for this shape is spinner + InlineError; UX-DR5 is satisfied by reusing the pane; the Skeleton docblock note lands in the D7 sweep.

## 8. Wire contract summary (verified against the shipped BE)

- `GET /attendance/me/monthly?from&to` (TECHNICIAN) → `{ from, to, today, summary{9 keys}, weeklyOffs: number[], upcomingHolidays: [{holidayDate, holidayName}] }`; 403 ATTENDANCE_NOT_TRACKED (none ONLY — upcoming/history_only 200); 422 ATTENDANCE_INVALID_RANGE (from > to, span > 31, to > tenant-today). `today` shipped `aa1b6c1` (verified; the draft's a3c8aa8 attribution was wrong).
- `GET /attendance/me/day-statuses?from&to` (TECHNICIAN) → `{ today, days: DayStatusRow[] }`; span ≤ 62; NO future-to 422 — hence D3's echo gate and the › bound.
- `GET /attendance/me/access` (TECHNICIAN) → `AttendanceAccess` + **`attendanceEndedOn: string | null` (NEW, D2 — history_only-only by the CASE gate)**.
- `GET /attendance/me/leave` (+ preview/POST) — unchanged (17-x); works in every access state.
- `GET /attendance/me/corrections` (TECHNICIAN, 18-2) — unchanged; feeds the day sheet's history me-scoped.

## 9. Adversarial review + step-03 triage record (2026-09-30)

Three passes: wire-truth lens (8 findings), UX/state lens (11 findings), UX design pass (4 rulings + 3 findings). Triage: each finding source-verified before disposition (the reviewers' file:line citations re-checked against HEAD; the UX-state P1 re-derived independently from `monthly.ts:180-182` + `attendanceDayStatus.ts:259-261` before accepting).

| # | Sev | Finding → Disposition |
|---|---|---|
| 1 | P1 | Bootstrap plain-range fetch of the CURRENT month 422s (`to > tenant-today`) ~29/30 days; Retry re-derives the same 422 (no echo ever lands); the claimed 19-5 symmetry was false (19-5 seeds LAST month). → **ACCEPT:** D3 rewritten — the hook is GATED on the pane's echo (me/day-statuses never 422s a future to) and always clamps via `monthlyWindow`; no plain-range fetch exists in this story. |
| 2 | P2 | useMyMonthly lacked the AppState-active refetch; midnight-crossing staleness unrecorded. → **ACCEPT:** hook gains focus + AppState silent refresh; D8 records the never-backgrounded-midnight acceptance. |
| 3 | P2 | The › bound's `today` anchor unnamed — two echoes could disagree. → **ACCEPT:** ONE canonical clock (the pane's report echo) drives window clamp, so-far test and bound (D3/D5). |
| 4 | P2 | yearMonth change did not pin data-clearing — September's chips could paint under October's title. → **ACCEPT:** D3 pins the runFetch posture on param change; test 2. |
| 5 | P2 | The bootstrap misdescribed the 19-5 idiom (correction is a PARAMETER load with re-arm; navigated = ‹/› only). → **ACCEPT:** D5 rewritten to the faithful idiom; test 3 pins. |
| 6 | P2 | history_only bootstrap opened on today's empty month. → **ACCEPT:** D5 targets `min(todayMonth, endedMonth)`; null-date fallback recorded. |
| 7 | P3 | Mid-view flip semantics accidental (tree-structure-dependent). → **ACCEPT:** D1 pins per-branch mounting + remount-on-flip; flip test added. |
| 8 | P2 | D7's "no test imports the lab" FALSE — `AttendanceHomeScreen.test.tsx:203-209` pins the tile + route; sweep list missed `dayStatusVisual` docblocks + the release tripwire. → **ACCEPT:** D7 expanded (items 4-6). |
| 9 | P3 | Two stacked identical "Retry" buttons; month-switch height jump. → **ACCEPT:** summary Retry gains "Retry month summary"; D8 records the accepted height-jump (UX Q4 keeps the pane posture). |
| 10 | P3 | Migration must re-assert `security_invoker` + grants (house pattern). → **ACCEPT:** pinned in D2. |
| 11 | P2 | Test-plan gaps (a)-(h): no-echo bootstrap, param-change clearing, access flips, the ACTIVE › bound, echo identity, AppState refetch, history_only bootstrap month, correction re-arm. → **ACCEPT:** all folded into §5. |
| 12 | P2 | (Wire F1) `attendance_ended_on` ungated — a re-enrolled active employee would carry a stale ended date; "active → null" pin false. → **ACCEPT:** the CASE gate (history_only-only) in D2; pins now true invariants. |
| 13 | P3 | (Wire F3) SQL type nits: daterange (not tstzrange) → `'infinity'::date`; `::date` cast dropped. → **ACCEPT** (D2 SQL final form). |
| 14 | P3 | (Wire F4) The journey-suite sentence referenced a nonexistent access step. → **ACCEPT:** deleted (§5.7 covers the e2e pin only). |
| 15 | P3 | (Wire F5) `today` echo attribution: aa1b6c1, not a3c8aa8. → **ACCEPT:** baseline + §8 corrected. |
| 16 | P3 | (Wire F6 + UX) The «d MMMM yyyy»/«d MMM» helpers don't exist; `formatLongDate` is the only shared long formatter. → **ACCEPT:** ended note uses `formatLongDate`; the «d MMM» row helper is new string surgery in monthlyModel (ONE month-name table). |
| 17 | P3 | (Wire F8 = #10) merged. |
| 18 | P2 | (Wire item-7) `captionSegments` isn't callable with the me payload — the meta line would be a second implementation. → **ACCEPT:** `summaryMetaSegments(summary)` exported from monthlyModel; `captionSegments` refactored onto it (owner output byte-identical, pinned). |
| 19 | P2 | (UX Q3) upcoming holidays for history_only → HIDE. → **ACCEPT (overturns the draft);** test 3 pins the absence. |
| 20 | P2 | (UX copy) Meta line's config segment dropped ("weekly off" ×3 on one screen); summary error copy gains the recovery sentence; holiday rows get comma a11y labels. → **ACCEPT:** copy table final. |
| 21 | P2 | (UX a11y) Per-line labels would announce the worked number twice. → **ACCEPT:** D9's one-element grouped label (recipe from MonthlyEmployeeRow); exact strings pinned. |
| 22 | P3 | (UX) Skeleton docblock pre-commitment drifts (Q4 keeps the spinner posture). → **ACCEPT:** D7.5 sweep item. |

Dismissed: none — every finding survived source verification (the two-lens + design structure worked; the reviewers cross-confirmed each other on the lab test (F2=#8), the migration hygiene (F8=#10) and the echo coupling (#3)).

**Frozen for build on the strength of: every route/shape/guard claim verified against HEAD by the wire lens (16-point verified list); the P1 fixed structurally (echo gate), not palliatively; the UX rulings grounded in cited DS tokens/precedents.**

## 10. Code review record (`/bmad-code-review`, 2026-09-30 — three lenses + step-03 triage)

Build result first: fenzo-app 223 suites/2760 tests + tsc clean (pre-patch), fenzit-be 90 suites/1421 + typecheck clean, edited e2e 71/71; migration MCP-applied (column live, grants re-verified: anon/authenticated denied, service_role select) and the BE prereq pushed `8f791a1` (Render deployed, health 200) BEFORE the FE commit per the ladder.

Three lenses ran (contract hunter / acceptance auditor / blind-spot). Consolidated: **0 P1 · 4 P2 · 13 P3** → step-03 triage (each finding source-verified before disposition; two reviewers independently confirmed the same objects — the lab-test pin, the migration grants, the echo coupling):

| # | Sev | Finding → Disposition |
|---|---|---|
| R1 | P2 | (Blind #1) A check-in never reached the pane: today's day sheet read "Not tracked" seconds after the card above said "Checked in" — the pane's non-clearing `refresh` handle existed and was never called. → **ACCEPTED + PATCHED:** the parent derives a today-facts fingerprint (`date|checkinAt|checkoutAt`) and passes it as `todaySignal`; a genuine CHANGE (first observation armed, repeats/null inert) fires the pane's in-place refresh — one GET, no spinner. Pinned (3 assertions incl. the arm). |
| R2 | P2 | (Contract #1) A silent-refresh SUCCESS left a standing first-load error — "Couldn't load…" above a loaded summary. → **ACCEPTED + PATCHED:** `refresh()` success now `setError(null)`; pinned. |
| R3 | P2 | (Blind #4) A silent-refresh FAILURE painted the hard first-load copy over live chips. → **ACCEPTED + PATCHED:** the section's error posture is DATA-AWARE — no summary → the hard copy + labelled Retry (unchanged); live chips → the stale-note InlineError `"Couldn't refresh just now — these numbers may be out of date."` (the AttendanceSummaryView vocabulary; no Retry — a Retry here would clear-and-refetch for no new information; the next focus/AppState revalidates). Pinned both postures. |
| R4 | P2 | (Acceptance #1) The FLIP remount pin pushed from the mock's RENDER BODY — it counted renders; a hoisted single-instance section would have passed it byte-identically (empirically proven by the auditor's scratch host). The shipped code was correct; the pin was weak. → **ACCEPTED + PATCHED:** the probe now pushes from a mount-scoped `useEffect([], …)` — a hoist fails the pin. |
| R5 | P3 | (Blind #2) Focus fires an unthrottled me/monthly GET on every push/pop round trip. → **ACCEPTED + PATCHED (scoped):** the focus path is gated by the shared `ACCESS_REFRESH_MIN_GAP_MS` (30s); AppState-active stays UNCONDITIONAL (the midnight case is load-bearing); Retry is a separate ungated path. Pinned. |
| R6 | P3 | (Contract #5/Acceptance #2) act() warnings — the AppState-fired refresh resolves outside act in tests. → **ACCEPTED + PATCHED where owned:** the new/heavy tests wrap fire+settle inside one act. The AttendanceMyMonth file retains 2 warnings that appear ONLY in the full-file run (cross-test microtask timing; per-test runs are 0-warning) — recorded as accepted hygiene debt. |
| R7 | P3 | (Contract #2/#3, Acceptance a/b) The spec-vs-code deviations (shared `toAccessStateResponse` mapping — the owner roster additively carries `attendanceEndedOn`; `MyMonthSummary`/`AttendanceLeaveSection` splits; `MY_MONTHLY_ERROR_COPY` export; the styled-Pressable Retry because `Button` doesn't forward accessibilityLabel). → **ACCEPTED as recorded deviations:** every pin on the affected surfaces is `toMatchObject` or was updated; FE roster normalizer whitelists; docs amended. |
| R8 | P3 | (Contract #6, informational) The active › bound uses `>=` where D5's literal is `===` — strictly stronger (also disables a device-seeded month ahead of the echo), the never-snap-back doctrine preserved. → **ACCEPTED as a spec footnote; no change.** |
| R9 | P3 | (Blind #3) history_only seed-window burn: if the pane echo lands before the access refetch, the bootstrap corrects once on a NULL ended date and a later date doesn't re-open it (the employee lands on the empty today-month, ‹ reachable, self-heals on remount). → **DEFERRED, recorded:** near-unreachable (access is in flight from boot before the pane echo in the real lifecycle), self-healing, and the airtight fix (re-open the correction on a null→date transition) adds state-machine surface the one-shot doctrine deliberately avoids. |
| R10 | P3 | (Contract #4, environmental) Full-parallel jest runs flake under machine load (stale workers; disk 98% full on this Mac); every flagged suite passes in isolation. → **NO CODE CHANGE; environmental.** Also noted: `bun run lint` has no ESLint config at baseline (pre-existing housekeeping item, not this story). |
| R11 | P3 | (Contract, informational) §5.1's shared-validator pin pins behavior, not the call graph — an inlined fork would pass. Inherent same-module limit; the import is additionally pinned in the build's test. → **ACCEPTED as-is.** |

**Post-patch verification (this session, serial):** fenzo-app `bun run test` → **223 suites / 2765 tests, all passing** (+5 review pins); `bunx tsc --noEmit` → clean. fenzit-be untouched by the patches (FE-only; BE stands at `8f791a1`).

**Device walkthrough:** BLOCKED at review time — the Pixel 6 is not attached. The §6 plan stands; the FE commit waits for it (the run's standing order: walkthrough → review → commit; here review ran first because the code-only lenses don't need the device, and the commit gates on the walkthrough).
