# Spec — Story 19-4: Owner dashboard UI (Frontend)

- **Story:** 19-4 (FR-24, UJ-1) — the owner's today snapshot: five KPI tiles, the two flag strips, the office filter, and the FE notification-mirror completion for the four 19-1 reminder events (fold-in; see D8 for why it lands here).
- **Repo:** fenzo-app only. BE already merged & deployed (fenzit-be a3c8aa8): `GET /api/v1/attendance/dashboard?officeId=` per spec-19-1-to-19-3 §D5.
- **Baseline:** fenzo-app at the 18-4 commit (this spec is written while 18-4 is verified-but-uncommitted; 19-4's build starts only after 18-4 is committed — one story in the tree at a time).
- **Status:** draft → adversarial review → triage → frozen for build.
- **Sources:** epics-attendance-leave.md §Story 19.4 (ACs quoted where they bind); prd.md FR-24 ("The Owner sees today's snapshot: number of Tracked employees, In progress (checked in), Not checked in yet, Late, on leave, plus flags from past days until handled: Checkout missing and Fake location attempt. It can be filtered by Office."); spec-19-1-to-19-3 §D5 (the wire this screen reads) and §D3 (the four reminder events whose FE mirror lands here); ARCHITECTURE-SPINE UX-DR5 ("one shared skeleton — generalize ReportSkeleton, used here first"); AD-13/AD-19/NFR-10 (notification registry mirror + generic-card fallback); FR-22 ("A Reminder appears in the in-app notification list" — the FE half must ship somewhere in Epic 19; the BE D3 note assigns "the FE registry mirror and card rendering" to the Epic 19 FE stories, and 19-4 is the owner-workflow story the three attendance reminders belong to).
- **Out of scope:** the monthly view (19-5), the self view (19-6), any write route (the dashboard is strictly read-only), flag-row deep-links into a day calendar (the production calendar host arrives with 19-5 — recorded as deferred in §6), and any ack UI for fake-location attempts (18-2 owns acknowledgements; none shipped on FE, and 19-4 only LISTS the flags).

## 1. Fix-placement analysis (per the root-CLAUDE.md rule)

| Concern | Layer | Why |
|---|---|---|
| Tiles/flags numbers | **BE** (already shipped, spec-19-1-to-19-3 §D5) | The engine is the single FR-10 source; the FE never recounts. |
| Skeleton generalization | **fenzo-app** (components/ui) | UX-DR5 is a presentation-kit concern; the BE has no analogue. |
| Office filter list | **fenzo-app** (officesService.list, existing) | The roster's office list is an existing FE resource; no new route. |
| Reminder card rendering | **fenzo-app** (registry mirror + builders) | AD-13's mirror rule: both sides extend in the same commit pair; the BE half shipped with a3c8aa8, so the FE half is due. |

## 2. Design decisions (locked before implementation)

**D1 — Route + entry.** New owner-stack route `AttendanceDashboard: undefined` in `RootStackParamList` (screen file `src/features/attendance/dashboard/AttendanceDashboardScreen.tsx`). Entry: a NEW FIRST tile on `AttendanceHomeScreen` — icon `LayoutDashboard`, `iconBg` the leave-tile's treatment (the Tile primitive's medallion pattern), title **"Today"**, subtitle **"Who's in and who's not"** → `navigation.navigate('AttendanceDashboard')`. The dashboard is its own screen (the epic's "Given the Dashboard screen"), not AttendanceHome content; AttendanceHome keeps its setup gate and back-fallback behaviours untouched (the new tile renders only past the gate like its siblings). The Component-lab dev tile stays (it retires in 19-5/19-6).

**D2 — Skeleton generalization (UX-DR5).** New `src/components/ui/Skeleton.tsx`, exported from the ui kit index: `Skeleton({ rows = 3 }: { rows?: number })` — the ReportSkeleton anatomy MOVED VERBATIM (opacity pulse 0.5→1→0.5, 800 ms, `Easing.inOut(Easing.ease)`, `useNativeDriver: true`, blocks `colors.borderSubtle`, radius 8, height 80, container `gap: spacing.s3`). `features/reports/components/ReportSkeleton.tsx` is DELETED and its one consumer (`ReportsScreen`) renders `<Skeleton />` — a one-consumer migration, no dead code, no visual change (the ReportsScreen snapshot tests already pin the loaded states, and the first-load branch swaps a component of identical output). The dashboard is the first NEW consumer ("used here first"); 19-5/19-6 reuse it, never rebuild. A `Skeleton.test.tsx` pins rows-count + pulse presence (the old component had NO test — this closes that gap too).

**D3 — Data service.** New `src/services/resources/attendanceDashboard.ts`:
- `fetchDashboard(officeId?: string)` → `GET /attendance/dashboard` with `officeId` appended (encodeURIComponent) only when provided. No idempotency key (read).
- Response type + fail-closed normalizer (the 18-3 fetch-level rule): `{ date: string; counts: { tracked; checkedIn; notCheckedIn; late; onLeave } (each a non-negative integer — a negative/missing/non-number THROWS); flags: { checkoutMissing: CheckoutMissingRow[]; fakeLocationAttempt: FakeLocationRow[] } }` where `CheckoutMissingRow = { employeeId, employeeName, workDate (YYYY-MM-DD regex-checked), officeName }` and `FakeLocationRow = CheckoutMissingRow + { attemptCount: number }`. An unknown shape throws (the whole fetch rejects — never a partial render).
- Re-exported via the resources index in the same change.

**D4 — KPI tiles.** Dashboard-local `KpiTile` (one file with the screen or a sibling component file — builder's call under the ≤300-line rule): a non-interactive `Card` (no Pressable — the AC's "tapping does nothing") with the big count (`typography` display weight, `colors.textStrong`) over the label (`caption`, `colors.textMuted`). Five tiles: **Tracked / Checked in / Not checked in / Late / On leave** (FR-24's vocabulary verbatim; the epic's labels). Grid: **3 per row** (AC), rows 3+2, tile width `(screenWidth − 2·screenMargin − 2·gap) / 3` (the HomeHeader `cardSize` formula, thirded), `gap: spacing.s3`. All tiles neutral (counts are answers, not states — no status hue on a number; the a11y label carries the pairing: `"«Label»: «n»"`). The documented checkedIn∩onLeave overlap (a checked-in half-day-leave counts in both) renders as-is — the tiles are five separate questions, no summing invariant is promised or displayed.

**D5 — Flag strips.** Two strips, the `OverdueStrip` pattern exactly (docblock cites it): a `Pressable` (`accessibilityRole="button"`, pressed opacity 0.8) wrapping a `Card padding="md"`, row anatomy icon → label (`labelStrong`) → count chip (status-bg pill, bodyStrong) → `ChevronRight`; row `minHeight: touch.min`, `gap: spacing.s2`. Strip 1 **"Checkout missing"** — icon = the 18-3 checkout-missing flag icon from `dayFlagVisuals`' table (brand-consistent with the calendar's flag), chip in that flag's status family. Strip 2 **"Fake location attempt"** — the 18-3 fake-location flag icon, same treatment. Counts = `flags.checkoutMissing.length` / `flags.fakeLocationAttempt.length`; a strip renders ONLY when its count > 0 (the OverdueStrip conditional-render idiom); the two strips sit in one `gap: spacing.s3` block below the tiles. Tap → opens that flag's list sheet (D6).

**D6 — Flag list sheets.** One `Sheet` component (`FlagListSheet`, dashboard-local) serving both kinds — `visible/onClose/title/rows`, detents `['auto']`: title **"Checkout missing"** / **"Fake location attempts"**; rows show `employeeName` (bodyStrong) + the date as "{Weekday}, {d} {Month}" (the `daySheetTitle`/month-label surgery helpers — string surgery, never a Date) + `officeName` (caption, textMuted); fake-location rows append "· «n» «attempts|attempt»". Wire order preserved (workDate asc, then name — BE §D5). Rows are plain Views (NOT pressable): the day-level action (open the calendar, correct the day) arrives with 19-5's production calendar host — deferred honestly, recorded in §6. Back/Android-back dismiss (the Sheet default); announced on present (the a11y floor idiom).

**D7 — Office filter.** A filter row between the header and the tiles: a pressable field styled as the DS `Select` (chevron-down, border, radius) reading **"All offices"** when unfiltered, else the office's name. Tap → `OfficeFilterSheet` (a Sheet listing **"All offices"** then each active office from `officesService.list(false)` — name rows, the picked one check-marked, the TechnicianPicker rows-variant check idiom). Picking → refetch with that officeId; "All offices" → refetch without. A `Select` component is rejected (unbounded office count → a scrolling sheet, not a dropdown). The BE's unknown-office 200-with-zeros contract renders honestly (zeros + empty flags) — a filter is not an entity fetch, and the FE adds no existence check.

**D8 — FE notification mirror + reminder cards (the FR-22/FR-23 FE completion, folded here).** The BE D3 note assigns the FE mirror to the Epic 19 FE stories; the three attendance reminders belong to the owner/employee "who's in today" workflow this story builds, and `leave.pending_reminder` rides the same commit to keep ONE mirror change (the epics leave it unassigned; splitting a registry mirror across stories would break AD-13's same-commit rule).

- `src/features/attendance/notifications/notificationEvents.ts`: `ATTENDANCE_NOTIFICATION_EVENT` gains exactly **4** entries, mirroring the BE registry character-for-character (the mirror test pins each literal): `REMINDER_CHECKIN: 'attendance.reminder_checkin'`, `REMINDER_CHECKOUT: 'attendance.reminder_checkout'`, `REMINDER_NOT_CHECKED_IN: 'attendance.reminder_not_checked_in'` (entity `attendance`), and `leave.pending_reminder` lands in the LEAVE side's enumeration (`leaveNotificationModel.ts` owner list) with entity `leave` — exactly as the BE D3 table rows them (recipients, payloadFields `{ workDate }` / `{ workDate, checkinAt }` / `{ officeName, notCheckedInCount, workDate }` / `{ pendingCount }`, dedupeKeyShapes verbatim).
- Classification: the three `attendance.reminder_*` types → action `'attendance'`; `leave.pending_reminder` → action `'leave'` (added to `LEAVE_OWNER_EVENTS`).
- Card data (a new builder arm in `notificationEventRegistry.ts` or the attendance module — builder's call, one implementation): title/message in simple English from the payload — `reminder_checkin` → "Check-in reminder" / "You haven't checked in yet today."; `reminder_checkout` → "Check-out reminder" / "You haven't checked out yet today."; `reminder_not_checked_in` → "Not checked in" / "«n» haven't checked in at «office»." (singular/plural on n); `leave.pending_reminder` → "Pending leave" / "«n» leave request«s» waiting for approval.".
- Taps: `reminder_checkin`/`reminder_checkout` (the employee's own) → the guarded `'TechnicianTabs' → Attendance` navigation (the existing attendance-card idiom with the reachability guard); `reminder_not_checked_in` → `AttendanceDashboard` (this story's screen — the summary's home); `leave.pending_reminder` → `OwnerLeave { tab: 'pending' }`. AD-19's unknown-type generic fallback is untouched (still renders anything unclassified).
- The mirror test + `notificationEventRegistry.test.ts` + `leaveNotificationModel.test.ts` extend in the same change (the 14-2/16-x mirror discipline).

**D9 — Screen states (the standard postures).**
- First load: `<Skeleton />` (D2) in place of tiles+flags; the filter row renders immediately (it is static chrome).
- Refetch discipline: focus + AppState-`active` refetch (the `useCheckInOut`/`RealMonthPane` idiom) — in-place swap, NO clearing spinner after first load (the 18-4 D5 posture generalized to a read screen); errors on a REFETCH keep the last-good render and surface the InlineError + Retry BELOW the content.
- First-load failure: InlineError + Retry in place of tiles+flags (nothing stale to keep).
- `tracked === 0`: the tile grid is REPLACED by an `EmptyState` — title "No one is tracked today", body "Add employees to attendance to see today's summary here." — with the flags strips still rendering if any (a flag can exist with zero today-tracked employees; it is past-day truth). `tracked > 0` renders the five tiles even when individual counts are 0.
- The `date` echo renders nowhere (the screen IS today; the wire echo is consumed for the fail-closed shape only).

**D10 — Loading budget.** One dashboard fetch per appearance (focus counts as one); the flags ride the same response — no second round-trip from the FE (the BE's targeted flag reads are its own §D5 affair).

## 3. Copy table (all user-visible strings; simple English, house punctuation)

| String | Where |
|---|---|
| Today / Who's in and who's not | AttendanceHome tile |
| Tracked / Checked in / Not checked in / Late / On leave | KPI tiles |
| Checkout missing / Fake location attempt | strips |
| Checkout missing / Fake location attempts | sheet titles |
| · «n» attempts / · 1 attempt | fake-location sheet rows |
| All offices / «Office name» | filter field |
| No one is tracked today / Add employees to attendance to see today's summary here. | empty state |
| Couldn't load the dashboard. Check your connection and try again. | first-load error (InlineError) |
| Retry | error button (the house secondary Button) |
| Check-in reminder / You haven't checked in yet today. | card |
| Check-out reminder / You haven't checked out yet today. | card |
| Not checked in / «n» haven't checked in at «office». (1 hasn't checked in at «office».) | card |
| Pending leave / «n» leave request«s» waiting for approval. (1 leave request waiting…) | card |

Card titles/messages live beside the existing card builders' copy. A11y strings: `"«Label»: «n»"` per tile; strips mirror OverdueStrip's label idiom (`"Checkout missing, «n»"`).

## 4. Code layout (files ≤ 300 lines, house structure)

```
src/components/ui/Skeleton.tsx                    # D2 (ux-DR5) + test
src/services/resources/attendanceDashboard.ts     # D3 (+ normalizer) + test
src/features/attendance/dashboard/
  AttendanceDashboardScreen.tsx                   # the screen: filter row, tiles, strips, states
  dashboardModel.ts                               # pure: tile list build, date labels, sheet-row build
  KpiTile.tsx           (may fold into the screen file under the line rule)
  FlagListSheet.tsx
  OfficeFilterSheet.tsx (may share FlagListSheet's file if small)
  AttendanceDashboardScreen.test.tsx
src/features/attendance/home/AttendanceHomeScreen.tsx  # + the Today tile (D1)
src/navigation/types.ts                                # + AttendanceDashboard route
src/features/notifications/*                           # D8: registry + builders + taps
src/features/reports/ReportsScreen.tsx                 # D2: ReportSkeleton → <Skeleton />
```

## 5. Test plan (jest/RTR, the house idioms)

1. `Skeleton.test.tsx`: rows default 3 / custom N; pulse Animated.View count; style pins.
2. `attendanceDashboard.test.ts`: route + optional encoded officeId; happy-shape pass-through; fail-closed throws (bad count type/negative, missing flag array, bad workDate, non-object rows); `flags` rows keep attemptCount only on fake-location rows.
3. `dashboardModel.test.ts`: tile list (order + a11y labels), strip visibility (count 0 → absent), sheet-row text ("Monday, 29 September"-style), attempt singular/plural, empty-state predicate (tracked === 0).
4. `AttendanceDashboardScreen.test.tsx` (mocked service): first-load Skeleton swap; tiles render the five counts; strips hidden at 0 / shown + tappable at >0 → sheet opens with the rows; office filter: field shows "All offices" → sheet lists offices + All → pick → refetch carries officeId + field shows the name; refetch-on-focus/AppState keeps last-good (no clearing spinner); first-load failure → InlineError + Retry refetches; tracked 0 → EmptyState; tile non-interactive (no Pressable in the tile subtree).
5. Mirror: `notificationEvents.test.ts` + registry + leave-model tests extended per D8; a builder test pins the four cards' title/message/tap targets; the unknown-type generic fallback test still passes untouched.
6. `AttendanceHomeScreen.test.tsx`: the new tile renders first + navigates.

## 6. Device walkthrough plan (draft — Ayush, physical Pixel 6)

Attendance → **Today** tile → the Skeleton shows once → the five tiles render with the production truth (Arya tracked; expected: checkedIn/notCheckedIn per her live record — read the DB before asserting). Flags: if no unresolved flag exists, SEED honestly via DB (one past-day record with check-in and no checkout + no adjudicating override → Checkout missing; one `attendance_attempts` row `outcome='mocked'`, `acknowledged_at` null → Fake location attempt) and verify strip → sheet → rows + attempt count; acknowledge/resolve via the product's own paths where possible (a correction fixes checkout-missing live — the 18-4 sheet is lab-only until 19-5, so resolve via DB + note, or leave the seed recorded). Office filter: pick the real office → tiles re-scope; pick All offices → restore. Reminder cards: trigger one real reminder (move the wall clock is impossible — instead INSERT a notifications row shaped exactly as `attendance_run_reminders()` writes it, dedupe-keyed so the real job never duplicates) → the card renders with title/message + tap → the right screen. AppState refetch: background/foreground → in-place update. Honest restore: any seeded DB row is deleted after the walkthrough and recorded here; the reminder notification row stays dedupe-keyed (or deleted) per what the run did.

## 7. Open questions

None blocking — D8's fold-in is the only judgment call, resolved above (AD-13's same-commit mirror rule beats story-size tidiness; recorded for the reviewer to challenge).
