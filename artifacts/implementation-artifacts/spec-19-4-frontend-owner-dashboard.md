# Spec — Story 19-4: Owner dashboard UI (Frontend)

- **Story:** 19-4 (FR-24, UJ-1) — the owner's today snapshot: five KPI tiles, the two flag strips, the office filter, and the FE notification-mirror completion for the four 19-1 reminder events (fold-in; see D8 for why it lands here).
- **Repo:** fenzo-app only. BE already merged & deployed (fenzit-be a3c8aa8): `GET /api/v1/attendance/dashboard?officeId=` per spec-19-1-to-19-3 §D5.
- **Baseline:** fenzo-app at the 18-4 commit (this spec is written while 18-4 is verified-but-uncommitted; 19-4's build starts only after 18-4 is committed — one story in the tree at a time).
- **Status:** draft → adversarial review (2026-09-30, §8) → triage (applied, §8) → **frozen for build**.
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

**D1 — Route + entry.** New owner-stack route `AttendanceDashboard: undefined` in `RootStackParamList` (screen file `src/features/attendance/dashboard/AttendanceDashboardScreen.tsx`). Entry: a NEW FIRST tile on `AttendanceHomeScreen` — icon `LayoutDashboard`, `iconBg` the leave-tile's treatment (the Tile primitive's medallion pattern), title **"Today"**, subtitle **"Who's in and who's not"** → `navigation.navigate('AttendanceDashboard')`. Entry FACTS (verified): AttendanceHome is reached from the **More tab** (`MoreScreen` → `navigation.navigate('AttendanceHome')`), and today's tile order is Leave → Offices → Settings → (dev) Component lab — "new FIRST tile" means **above Leave**. The leave-tile's `iconBg` treatment is the token **`colors.status.progress.bg`** — use the token, not a sibling-tile reference. The dashboard is its own screen (the epic's "Given the Dashboard screen"), not AttendanceHome content; AttendanceHome keeps its setup gate and back-fallback behaviours untouched (the new tile renders only past the gate like its siblings). The Component-lab dev tile stays (it retires in 19-5/19-6).

**D2 — Skeleton generalization (UX-DR5).** New `src/components/ui/Skeleton.tsx`, exported from the ui kit index: `Skeleton({ rows = 3, height }: { rows?: number; height?: number })` — the ReportSkeleton anatomy MOVED VERBATIM at spec time; as-built the block gained a sheen sweep over the pulse and the optional `height` prop reshapes every row (the tile-shaped loading grid: dashboard passes 158). Every other constant is the verbatim move (opacity pulse 0.5→1→0.5, 800 ms, `Easing.inOut(Easing.ease)`, `useNativeDriver: true`, blocks `colors.borderSubtle`, radius 8, height 80, container `gap: spacing.s3`). `features/reports/components/ReportSkeleton.tsx` is DELETED and its one consumer (`ReportsScreen`) renders `<Skeleton />` — a one-consumer migration, no dead code, no visual change (the ReportsScreen snapshot tests already pin the loaded states, and the first-load branch swaps a component of identical output). The dashboard is the first NEW consumer ("used here first"); 19-5/19-6 reuse it, never rebuild. Safety-net fact (verified): the repo has ZERO snapshot assertions — `ReportsScreen.test.tsx` pins the loaded states with react-test-renderer prop/child assertions, not snapshots; the pins stand as-is and the no-visual-change claim rests on the identical-output swap plus those assertions (state it honestly in the review record). A `Skeleton.test.tsx` pins rows-count + pulse presence (the old component had NO test — this closes that gap too).

**D3 — Data service.** New `src/services/resources/attendanceDashboard.ts`:
- `fetchDashboard(officeId?: string)` → `GET /attendance/dashboard` with the `officeId` param passed RAW to apiClient (`{ params: { officeId } }`) only when provided — apiClient's paramsSerializer percent-encodes the value exactly once (a pre-encode here would double the escapes; as-built amendment). No idempotency key (read).
- Response type + fail-closed normalizer (the 18-3 fetch-level rule): `{ date: string (YYYY-MM-DD regex-checked — same rule as workDate); counts: { tracked; checkedIn; notCheckedIn; late; onLeave } (each a non-negative integer — a negative/missing/non-number THROWS); flags: { checkoutMissing: CheckoutMissingRow[]; fakeLocationAttempt: FakeLocationRow[] } }` where `CheckoutMissingRow = { employeeId, employeeName, workDate (YYYY-MM-DD regex-checked), officeName: string | null }` and `FakeLocationRow = CheckoutMissingRow + { attemptCount: non-negative integer (negative/missing/non-number THROWS) }`. **`officeName` is nullable on the wire (verified in `dashboard-response.model.ts`)** — the normalizer passes `string | null` through (it is a display-only field); a non-string non-null THROWS. An unknown shape throws (the whole fetch rejects — never a partial render).
- **As-built amendment (the 19-4 redesign):** the response gains the OPTIONAL `offices: DashboardOfficeStat[]` registry (`{ id, name, tracked, checkedIn }` each validated like a count when PRESENT) — absent → `null` ("no stats available", an older deployed BE, never a failure); present-but-malformed → the whole fetch still fails closed. **Cross-repo order (unchanged, applies to D3+FE):** the additive BE change merges/deploys `fenzit-be` FIRST, then `fenzo-app` — recorded here because §2/§3 above predate §9's note.
- Re-exported via the resources index in the same change.

**D4 — KPI tiles.** Dashboard-local `KpiTile` (one file with the screen or a sibling component file — builder's call under the ≤300-line rule): a non-interactive `Card` (no Pressable — the AC's "tapping does nothing") with the big count (`typography` display weight, `colors.textStrong`) over the label (`caption`, `colors.textMuted`). Five tiles: **Tracked / Checked in / Not checked in / Late / On leave** (FR-24's vocabulary verbatim; the epic's labels). Grid: **3 per row** (AC), rows 3+2, tile width derived as `(screenWidth − 2·screenMargin − 2·gap) / 3` — a fresh derivation (the HomeHeader `cardSize` source is a two-tile, ONE-gap formula; do not cite it as a source pattern, only as the house idiom for width-from-screenWidth), `gap: spacing.s3`. All tiles neutral (counts are answers, not states — no status hue on a number; the a11y label carries the pairing: `"«Label»: «n»"`). AS-BUILT AMENDMENT (the redesign mock): the neutrality claim is SUPERSEDED — each family tile now carries its status family's hue (icon chip, label, corner dot from the DS status tables) and the Tracked tile alone is the primary-blue accent with two sheen circles; the a11y pairing is unchanged. The documented checkedIn∩onLeave overlap (a checked-in half-day-leave counts in both) renders as-is — the tiles are five separate questions, no summing invariant is promised or displayed.

**D5 — Flag strips.** Two strips, the `OverdueStrip` pattern exactly (docblock cites it): a `Pressable` (`accessibilityRole="button"`, pressed opacity 0.8) wrapping a `Card padding="md"`, row anatomy icon → label (`labelStrong`) → count chip (status-bg pill, bodyStrong) → `ChevronRight`; row `minHeight: touch.min`, `gap: spacing.s2`. Strip 1 **"Checkout missing"** — icon from `DAY_STATUS_VISUALS.checkout_missing` (verified: `dayStatusVisual.ts` — the table KEY is snake_case `checkout_missing`, its `badgeStatus` string is 'checkoutMissing', icon `AlertCircle`; NOTE: there is NO checkout-missing entry in `dayFlagVisuals` — the day-flag table only has late/early rows). Strip 2 **"Fake location attempt"** — icon from the `dayFlagVisuals` `fake_location_attempt` row (verified: `ShieldAlert`, badge family `cancelled`). Conditional-render rule: the count-0 guard is a CALLER idiom (verified: `TodaysJobsSection` renders `{count > 0 ? <OverdueStrip/> : null}` — OverdueStrip itself always renders), preserved here. Counts = `flags.checkoutMissing.length` / `flags.fakeLocationAttempt.length`; a strip renders ONLY when its count > 0 (the OverdueStrip conditional-render idiom); the two strips sit in one `gap: spacing.s3` block below the tiles. Tap → opens that flag's list sheet (D6).

**D6 — Flag list sheets.** One `Sheet` component (`FlagListSheet`, dashboard-local) serving both kinds — `visible/onClose/title/rows`, detents `['auto']`: title **"Checkout missing"** / **"Fake location attempts"**; rows show `employeeName` (bodyStrong) + the date as "{Weekday}, {d} {Month} {year}" (pure string surgery over MONTH_NAMES built locally in `dashboardModel.ts` — verified: there is NO exportable month-label helper; `daySheetTitle` in `dayDetailModel.ts` is the surgery pattern to mirror, `RealMonthPane.monthTitle` is unexported; the year is ALWAYS shown because flag rows can come from a different calendar year) + office caption / attempt suffix — AS-BUILT AMENDMENT: date + office + attempts merge into ONE detail line via `flagRowDetail()` (`"{date} · «office» · «n» attempt«s»"`, the office segment dropped when `officeName` is null); the caption-as-separate-line shape above is superseded. Rows render unbounded (no cap/pagination — pre-launch volume is small; the Sheet's body scrolls; record in review if a cap is ever wanted). Wire order preserved (workDate asc, then name — BE §D5). Rows are plain Views (NOT pressable): the day-level action (open the calendar, correct the day) arrives with 19-5's production calendar host — deferred honestly, recorded in §6. Back/Android-back dismiss (the Sheet default); announced on present (the a11y floor idiom).

**D7 — Office filter.** A filter row between the header and the tiles: a pressable field styled as the DS `Select` (chevron-down, border, radius) reading **"All offices"** when unfiltered, else the office's name. Tap → `OfficeFilterSheet` (a Sheet listing **"All offices"** then each active office from `officesService.list()` — the no-arg default is list-all-active; verified — name rows, the picked one check-marked, the TechnicianPicker rows-variant check idiom). Sheet postures (added): while the offices fetch is in flight the sheet shows skeleton rows (the Skeleton primitive, rows=3); on failure it shows InlineError + Retry INSIDE the sheet (the house composition) — never an empty list. Picking → refetch with that officeId; "All offices" → refetch without. The offices fetch is a separate lightweight call scoped to sheet-open (D10's budget covers the dashboard fetch only). AS-BUILT AMENDMENT (the redesign): the fetch is no longer SHEET-ONLY — the same `officesService.list()` call also backs the Sites pill (D10 amendment): it runs alongside a load whenever the dashboard envelope carries no `offices` registry, so the pill shows the count without opening the sheet; its failure just hides the pill (never touches the tiles). A `Select` component is rejected (unbounded office count → a scrolling sheet, not a dropdown). The BE's unknown-office 200-with-zeros contract renders honestly (zeros + empty flags) — a filter is not an entity fetch, and the FE adds no existence check.

**D8 — FE notification mirror + reminder cards (the FR-22/FR-23 FE completion, folded here).** The BE D3 note assigns the FE mirror to the Epic 19 FE stories; the three attendance reminders belong to the owner/employee "who's in today" workflow this story builds, and `leave.pending_reminder` rides the same commit to keep ONE mirror change (the epics leave it unassigned; splitting a registry mirror across stories would break AD-13's same-commit rule).

- `src/features/attendance/notifications/notificationEvents.ts`: `ATTENDANCE_NOTIFICATION_EVENT` gains exactly **3** entries (the 4th lands in the leave enumeration below — in total this story mirrors 4 events), mirroring the BE registry character-for-character (the mirror test pins each literal): `REMINDER_CHECKIN: 'attendance.reminder_checkin'`, `REMINDER_CHECKOUT: 'attendance.reminder_checkout'`, `REMINDER_NOT_CHECKED_IN: 'attendance.reminder_not_checked_in'` (entity `attendance`), and `leave.pending_reminder` lands in the LEAVE side's enumeration (`leaveNotificationModel.ts` owner list) with entity `leave` — exactly as the BE D3 table rows them (recipients, payloadFields `{ workDate }` / `{ workDate, checkinAt }` / `{ officeName, notCheckedInCount, workDate }` / `{ pendingCount }`, dedupeKeyShapes verbatim). Mirror-context facts (verified): the FE mirror today holds only 2 entries (`holiday_added`/`holiday_removed`) — it is already BEHIND the BE; `attendance.fake_location` is an un-mirrored BE event this story deliberately leaves alone (18-2 owns acks) — record the residual ratio in review. Adding `leave.pending_reminder` to `LEAVE_OWNER_EVENTS` CONTRADICTS `leaveNotificationModel`'s own docblock ("deliberately stays on the generic card") and its pinned test — both flip in the same change.
- Classification: the three `attendance.reminder_*` types → action `'attendance'`; `leave.pending_reminder` → action `'leave'` (added to `LEAVE_OWNER_EVENTS`). WIRING FACT (verified): `notificationEventAction` today has NO owner arm for `attendance.*` — `isAttendanceEventType` is a technician-only prefix check and the owner report arm precedes it, so owner-side `attendance.reminder_not_checked_in` currently falls through to the generic arm. The 'attendance' ruling therefore ADDS an explicit arm for the `attendance.reminder_*` literals before the fall-through (role-agnostic for these three literals; the technician prefix path stays untouched).
- Card data (a new builder arm in `notificationEventRegistry.ts` or the attendance module — builder's call, one implementation): title/message in simple English from the payload — `reminder_checkin` → "Check-in reminder" / "You haven't checked in yet today."; `reminder_checkout` → "Check-out reminder" / "You haven't checked out yet today."; `reminder_not_checked_in` → "Not checked in" / "«n» haven't checked in at «office»." (singular/plural on n); `leave.pending_reminder` → "Pending leave" / "«n» leave request«s» waiting for approval.".
- Taps: `reminder_checkin`/`reminder_checkout` (the employee's own) → the guarded `'TechnicianTabs' → Attendance` navigation (the existing attendance-card idiom with the reachability guard); `reminder_not_checked_in` → `AttendanceDashboard` (this story's screen — the summary's home); `leave.pending_reminder` → `OwnerLeave { tab: 'pending' }`. AD-19's unknown-type generic fallback is untouched (still renders anything unclassified).
- The mirror test + `notificationEventRegistry.test.ts` + `leaveNotificationModel.test.ts` extend in the same change (the 14-2/16-x mirror discipline).

**D9 — Screen states (the standard postures).**
- Screen chrome: the screen is titled **"Today"** with the standard owner-stack back header (reuse the AttendanceSettings/AttendanceOffices header component — builder confirms the shared component at build time); the filter row (D7) renders below that header and above the content region.
- First load: `<Skeleton />` (D2) in place of tiles+flags; the filter row renders immediately (it is static chrome).
- Refetch discipline: focus + AppState-`active` refetch (the `useCheckInOut`/`RealMonthPane` idiom) — in-place swap, NO clearing spinner after first load (the 18-4 D5 posture generalized to a read screen). AS-BUILT AMENDMENT (the redesign): an EXPLICIT Refresh press is the exception — it ALSO re-shows the card shimmer (user direction mid-build: "when refresh is clicked shimmer should come again"); focus/AppState refetches keep the silent in-place swap. Errors on a REFETCH keep the last-good render and surface the InlineError + Retry BELOW the content (NOTE: InlineError has NO retry prop — "InlineError + Retry" is the house composition of InlineError plus a secondary `Button` labeled "Retry", as in RealMonthPane/ReportsScreen; verified).
- First-load failure: the same composition in place of tiles+flags (nothing stale to keep).
- `tracked === 0`: the tile grid is REPLACED by an `EmptyState` (props verified: `title` + `description` + mandatory `icon` — not "body"; icon `Users`) — title "No one is tracked today", description "Add employees to attendance to see today's summary here." — with the flag strips still rendering BELOW the EmptyState if any (a flag can exist with zero today-tracked employees; it is past-day truth; content order is: header → filter row → tiles/EmptyState → strips). `tracked > 0` renders the five tiles even when individual counts are 0.
- The `date` echo renders nowhere (the screen IS today; the wire echo is consumed for the fail-closed shape only).

**D10 — Loading budget.** ONE dashboard fetch per appearance, and the fetch discipline DEDUPES the first appearance: `useFocusEffect` performs the fetch, so the first focus IS the initial load (no separate mount fetch — never two round-trips in the first second); each later focus/AppState-active is a refetch. The flags ride the same response — no second round-trip from the FE (the BE's targeted flag reads are its own §D5 affair). AS-BUILT AMENDMENT (the redesign): ONE CONDITIONAL second call — the `officesService.list()` fallback (D7 amendment) rides alongside a load ONLY while the envelope's `offices` registry is absent (first look / an older deployed BE), so the Sites pill can show its count; once a dashboard fetch returns the registry, the fallback stops running. Its failure hides the pill and never touches the tiles.

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

**As-built additions (the redesign + review rounds):** `«n» Sites` / `1 Site` (the WorkspaceSelector pill — count-driven, hidden while a filter is active); "Filter by office, currently «selection»" (the field's a11y label); "Apply Filter" (the sheet's apply button) and "Reset" (its clear-selection chip); "Active" (OfficeCard's checked-in chip — only with an envelope stat, never fabricated); "No offices yet — add one from Attendance offices first." (the sheet's empty state); "Couldn't load the offices. Check your connection and try again." (the sheet's in-sheet failure banner); "Live Sync" (the Tracked tile's label chip) and "Auto" (its corner dot label); "% workforce present today" (the PresentCard caption suffix — `«n»% workforce present today`); the strip detail lines `No check-out recorded for «n» past day«s».` / `GPS spoofing blocked on «n» day«s».` (verified dashboardModel.ts); "Go back" (DashboardHeader back chip a11y) and "Refresh" (the header's refresh button); the present-bar a11y label `«n»% workforce present today` on every carrier (progressbar role).

Card titles/messages live beside the existing card builders' copy. A11y strings: `"«Label»: «n»"` per tile; strips mirror OverdueStrip's label idiom INCLUDING its singular/plural noun tail (verified: `"Overdue, 1 job" / "Overdue, 2 jobs"`) — `"Checkout missing, «n» «day|days»"` and `"Fake location attempt, «n» «day|days»"` (each row is an employee-day; the fake-location sheet then shows the per-row attempt count).

## 4. Code layout (files ≤ 300 lines, house structure)

```
src/components/ui/Skeleton.tsx                    # D2 (ux-DR5) + test
src/services/resources/attendanceDashboard.ts     # D3 (+ normalizer) + test
src/features/attendance/dashboard/
  AttendanceDashboardScreen.tsx                   # the screen: layout, postures, sheet wiring
  useDashboardData.ts                             # (as-built split) the load/refetch engine + failure seams
  dashboardModel.ts                               # pure: tile list build, date labels, sheet-row build
  KpiTile.tsx           (may fold into the screen file under the line rule)
  FlagListSheet.tsx
  OfficeFilterSheet.tsx (as-built: split OfficeCard out under the line rule)
  OfficeCard.tsx        (as-built, split from OfficeFilterSheet)
  PresentCard.tsx       (as-built, the grid's sixth cell)
  DashboardHeader.tsx, WorkspaceSelector.tsx, LoadErrorRetry.tsx  (as-built, the redesign's parts)
  AttendanceDashboardScreen.test.tsx
src/features/attendance/home/AttendanceHomeScreen.tsx  # + the Today tile (D1)
src/navigation/types.ts                                # + AttendanceDashboard route
src/features/notifications/*                           # D8: registry + builders + taps
src/features/reports/ReportsScreen.tsx                 # D2: ReportSkeleton → <Skeleton />
```

## 5. Test plan (jest/RTR, the house idioms)

1. `Skeleton.test.tsx`: rows default 3 / custom N; pulse Animated.View count; style pins.
2. `attendanceDashboard.test.ts`: route + optional encoded officeId; happy-shape pass-through; fail-closed throws (bad count type/negative, missing flag array, bad workDate, bad `date` echo, non-object rows, bad attemptCount); `officeName: null` passes through; `flags` rows keep attemptCount only on fake-location rows.
3. `dashboardModel.test.ts`: tile list (order + a11y labels), strip visibility (count 0 → absent), a11y labels with the noun tail, sheet-row text ("Monday, 29 September 2026"-style, year always), attempt singular/plural, null officeName row renders without an office caption, empty-state predicate (tracked === 0).
4. `AttendanceDashboardScreen.test.tsx` (mocked service): first-load Skeleton swap; EXACTLY ONE fetch on first appearance (no mount+focus double fetch); tiles render the five counts; strips hidden at 0 / shown + tappable at >0 → sheet opens with the rows; office filter: field shows "All offices" → sheet lists offices + All → pick → refetch carries officeId + field shows the name; office sheet in-flight skeleton rows + failure → InlineError + Retry inside the sheet; refetch-on-focus/AppState keeps last-good (no clearing spinner); first-load failure → InlineError + Retry composition refetches; tracked 0 → EmptyState with strips below; tile non-interactive (no Pressable in the tile subtree).
5. Mirror: `notificationEvents.test.ts` + registry + leave-model tests extended per D8; a builder test pins the four cards' title/message/tap targets; the unknown-type generic fallback test still passes untouched.
6. `AttendanceHomeScreen.test.tsx`: the new tile renders first + navigates.

## 6. Device walkthrough plan (draft — Ayush, physical Pixel 6)

Attendance → **Today** tile → the Skeleton shows once → the five tiles render with the production truth (Arya tracked; expected: checkedIn/notCheckedIn per her live record — read the DB before asserting). Flags: if no unresolved flag exists, SEED honestly via DB (one past-day record with check-in and no checkout + no adjudicating override → Checkout missing; one `attendance_attempts` row `outcome='mocked'`, `acknowledged_at` null → Fake location attempt) and verify strip → sheet → rows + attempt count; acknowledge/resolve via the product's own paths where possible (a correction fixes checkout-missing live — the 18-4 sheet is lab-only until 19-5, so resolve via DB + note, or leave the seed recorded). Office filter: pick the real office → tiles re-scope; pick All offices → restore. Reminder cards: trigger one real reminder (move the wall clock is impossible — instead INSERT a notifications row shaped exactly as `attendance_run_reminders()` writes it, dedupe-keyed so the real job never duplicates) → the card renders with title/message + tap → the right screen. AppState refetch: background/foreground → in-place update. Honest restore: any seeded DB row is deleted after the walkthrough and recorded here; the reminder notification row stays dedupe-keyed (or deleted) per what the run did.

## 7. Open questions

None blocking — D8's fold-in is the only judgment call, resolved above (AD-13's same-commit mirror rule beats story-size tidiness; recorded for the reviewer to challenge).

## 8. Adversarial review + triage record (2026-09-30)

Lens: adversarial only (`bmad-review`, single lens), on the draft spec with a code-claim verification pass over both repos (fenzo-app at 18-4 baseline `45abaf4`; fenzit-be `a3c8aa8`). 22 findings, all accepted; every patch is folded into §2–§5 above. Summary of what changed:

| # | Finding | Patch |
|---|---|---|
| 1 | Entry path + tile order unstated | D1: More-tab fact, "FIRST" = above Leave |
| 2 | "leave-tile's treatment" not a token | D1: token `colors.status.progress.bg` |
| 3 | "Snapshot tests pin loaded states" FALSE (repo has zero snapshots) | D2: safety net restated honestly (prop/child assertions) |
| 4 | `officeName` nullable on the wire (verified in BE model) | D3: pass-through `string \| null`; D6: caption only when present; test case added |
| 5 | attemptCount + `date` echo unvalidated | D3: non-negative-integer + YYYY-MM-DD rules; test case added |
| 6 | Tile-width formula provenance wrong (source is one-gap) | D4: fresh derivation, HomeHeader cited as house idiom only |
| 7 | dayFlagVisuals has NO checkout-missing row | D5: checkout → `DAY_STATUS_VISUALS.checkoutMissing`; fake-location → `fake_location_attempt` (ShieldAlert, 'cancelled') |
| 8 | Conditional render is a caller idiom | D5: cites TodaysJobsSection |
| 9 | A11y label lost the count noun | Copy table: noun-tail idiom pinned, days for both strips |
| 10 | No exportable month-label helper | D6: MONTH_NAMES built locally in dashboardModel |
| 11 | Yearless sheet rows | D6: year ALWAYS shown |
| 12 | Unbounded sheet unrecorded | D6: unbounded + Sheet scroll, honest note |
| 13 | Office-sheet loading/failure postures missing | D7: skeleton rows in flight; InlineError+Retry inside the sheet; D10 note |
| 14 | `list(false)` redundant | D7: `list()` no-arg default |
| 15 | "gains 4" ambiguous (4th lands in leave model) | D8: file gains 3, story mirrors 4 |
| 16 | FE mirror behind BE (fake_location un-mirrored) | D8: residual ratio recorded as deliberate |
| 17 | Owner-side `attendance.*` falls to generic today | D8: explicit arm for the three reminder literals added to the ruling |
| 18 | leave docblock + test pin contradict the change | D8: both flip in the same change |
| 19 | EmptyState props are title/description/icon | D9: corrected; icon `Users` |
| 20 | InlineError has no retry prop | D9: named as the house composition |
| 21 | First-appearance double-fetch possible | D10: first focus IS the initial load; screen test pins one fetch |
| 22 | Screen chrome + empty-branch order undefined | D9: "Today" header + content order (header → filter → tiles/EmptyState → strips) |

Nothing triaged out; no finding dismissed. Spec frozen for build on this state.

## 9. Build walkthrough record (2026-09-30 — the shipped redesign)

The build DID follow the frozen §1–§8 discipline for what survived, but the
user then supplied a full redesign mock mid-story and it supersedes parts of
D1–D9 deliberately. This section records what shipped, what the redesign
dropped, and the directed deviations — nothing here re-opens the spec; it is
the as-built record the code review will check against.

### 9.1 What shipped

- **Screen (supersedes D1's layout with the redesign mock):** "Today"
  header, then the workspace/office selector card (white, `radius.lg`,
  chevron-down — renders the pick, not a `Select`-styled filter field),
  then a 2-column KPI tile grid: Tracked, Checked in (with its percentage
  pill), Not checked in, Late, On leave. "Live Sync" row on the Checked-in
  tile face. CRITICAL strips: checkout-missing then fake-location attempt,
  each pressable → its list sheet (day + count rows, D6 semantics kept).
  Sites pill = "N Sites" on the header area when unfiltered (from the
  envelope `offices` count when present, else the offices fetch — never a
  fabricated number), hidden while an office filter is applied.
- **BE additive wire change (shipped in this story chain):**
  `DashboardResponse.offices: DashboardOfficeRow[]` `{id, name, tracked,
  checkedIn} — one tenant-wide engine grid per fetch, office tallies cut in
  code, `readOfficeRegistry()` returns ALL non-archived offices (zeros when
  none tracked); flags respect the selected office. No breaking surface
  touched.
- **FE envelope contract:** `offices` is OPTIONAL on the wire — absent →
  `null` ("no stats available"), present-but-malformed → the whole fetch
  fails closed. Tally subtitles/"Active" chips render ONLY from real stat
  rows; the fallback name-only registry never shows a fabricated number.
- **OfficeFilterSheet (the redesign mock, Image #2):** pick-then-apply.
  "All offices" card (LayoutGrid on a solid-primary chip) + one card per
  office (Building2 on a progress-bg chip), each with icon chip → title +
  tally subtitle → optional green "Active" chip → radio. Tap = set draft;
  Apply Filter commits (ArrowRight trailing icon); Reset reverts the draft
  (disabled while draft is already null); X/drag/back discard. Fixed 0.75
  detent + `scrollable`, so the list scrolls for a 15-office tenant inside
  the stretched card column; pinned footer is opaque with `s32` content
  clearance. Skeleton rows in flight; InlineError + Retry inside the sheet
  on failure of the office fetch (D7 posture kept for the fallback source);
  empty text: "No offices yet — add one from Attendance offices first."
- **The ui/Sheet footer inset fix (shared change, owning layer = ui/Sheet):**
  the pinned footer now carries `paddingBottom: max(system bottom inset, s2)`
  and an opaque `surfaceCard` background inside the Sheet's footer slot —
  on the edge-to-edge Pixel 6 the footer buttons were glued to the gesture
  bar. One fix for every sheet in the app (ReassignOfficeSheet,
  WeeklyOffOverrideSheet, HolidayFormSheet…), not re-invented per sheet.

### 9.2 Skipped mock items (data not available) and directed deviations

- **Skipped per mock's own escape hatch** ("extra items … whose data is
  not available can be skipped"): the "100% Total" headcount line (no
  total-headcount field on the wire), the Oct-24 calendar/date pill, the
  "LIVE" pill next to Live Sync.
- **Directed mid-build (user):** search bar in the sheet — dropped before
  build; list must be scrollable for many offices (the 0.75-detent
  ScrollView); lucide icons in the sheet (LayoutGrid / Building2 / Check /
  ArrowRight); the two footer buttons needed a bottom margin and app-theme
  colours (→ the ui/Sheet inset fix).
- **Directed deviations from D7:** the office filter is a selector CARD
  above the grid, not a "Select"-styled filter field; the sheet is
  pick-then-apply, not pick-and-commit. Both supersede D7 deliberately.
- **Deviation from D9's grid:** the redesign uses a 2-column tile grid —
  D9/D4's five-in-one-row derivation is superseded.
- D8 (notification mirrors), D10 (one-fetch budget), D5 strip semantics
  and all wire/a11y contracts are UNCHANGED by the redesign.

### 9.3 Test-harness record

- `jest.setup.js` gains the library's own `react-native-safe-area-context`
  jest mock (it is ESM-transpiled — `require(...).default`). THIS SENTENCE IS
  THE RECORD'S ONE AMENDMENT, mid-review: §2 originally read "Sheet.tsx hardens
  the hook with a zero-inset fallback" — the review's patch 22a removed it as
  a "dead guard", and it turned out NOT dead: it was the only thing standing
  between provider-less mounts and `jest.resetAllMocks()` wiping the library
  mock's `jest.fn` `useSafeAreaInsets` (proven by an error-boundary probe —
  without the guard, 18 suites red at `Sheet.tsx:166` the moment a mock-reset
  describe rendered a Sheet). The component stays clean per the review; the
  load-bearing part moved to the TOOLING — `jest.setup.js` now re-exposes
  `useSafeAreaInsets`/`useSafeAreaFrame` as plain functions (they are NOT
  `jest.fn`, so a reset cannot wipe them) that read the real
  SafeArea/Frame contexts with the zero-frame fallback. The final sweep's
  214 green suites include every pre-existing footer consumer that relied on
  the old guard's behaviour; the harness change is the honest substitute.
- Suite-local adjustments: Sheet.test + TimeField.test wrap their roots in
  a zero-inset SafeAreaProvider (and — because `renderer.update()`
  REPLACES the whole tree — re-apply the wrapper on every update).
- Final FE sweep before this record: originally 1724/1724 (28 suites) at spec time; the POST-REVIEW sweep after the 22 patch items and the splits is 2604/2604 passing (214 suites) under the working jest invocation (plain `bun run test` still red repo-wide on the pre-existing jest-runtime `readonly property` artifact — documented, not a 19-4 regression).

### 9.4 Honest-restore note

No DB seed was inserted for the walkthrough — the device run used the live
production truth (the user was live-testing leave + check-in flows
themselves that day: `leave_events` 2768–2772, one real attendance record
at Hero wala). Tile values seen on device matched DB truth at each look;
deltas between looks were live-data movement, not a dashboard defect. The
office-filter verification (apply Hero wala → 1 tracked / 1 checked in /
100% pill, strips re-scope; Reset + Apply → All offices restored, 3 Sites
pill back) was done with real data end-to-end.

Spec status: as-built, all 22 review patch items applied and checked off
(§10), the record amended in place (§2/§3/§4/§9), the device walkthrough
done (§9.4), the gap tests written during the review round (the standing
"tests after user confirmation" gate was met — the core was verified on
device first), and `/bmad-code-review` completed. Next gate: explicit user
consent → consent-gated commits in cross-repo order — `fenzit-be` merges/
deploys FIRST (additive `offices` change), then `fenzo-app`, then the spec +
sprint-status in `fenzit-meta`. No commit happens before that consent.

---

## 10. Code review record (`/bmad-code-review`, 2026-09-30)

Four review layers — Blind Hunter, Edge Case Hunter, Verification Gap Reviewer,
Acceptance Auditor — over the combined uncommitted diff (fenzo-app + fenzit-be;
5,053 lines). Triage: D decision-needed, P patch, W defer, R dismissed.
Dismissed claims (not real): officeId 422 validation missing (kept in
`dto/dashboard-query.dto.ts`); 44px refresh chip below `touch.min` (`touch.min`
is 44); flag reads not honouring the office filter (both reads take it,
`dashboard-flags.ts:134/197`); tracked rows with a null office id missing from
tallies (the enrolment ∩ assignment join at `dashboard.ts:189` guarantees an
office); fetch hang (the apiClient global timeout); a ≤0 tile width
(unreachable width); route role-gate absent (BE `@Roles(Role.OWNER)` +
owner-only entry surfaces, documented bypass comment); a technician receiving a
`dashboard` card (owner-only event recipients); FlagStrip `minHeight +10`
(mock-driven); docs outside the diff (they live here, in fenzit-meta).

### Review Findings

- [x] [Review][Decision] The new bottom-inset footer wrapper in the shared DS `Sheet` is consumed by five pre-existing footer consumers (HolidayFormSheet, WeeklyOffOverrideSheet, SetupWizard/WizardStepFrame, ReassignOfficeSheet, EditJobSheet) — device-verified only on the two 19-4 sheets; spot-check the other five footers on the Pixel 6 before commit.
  — RESOLVED 2026-09-30 (Pixel 6, dump-guided taps on 1C301FDF6002ZB): Weekly-off override sheet PASS; Add-holiday form sheet PASS (Save with a proper bottom inset, scroll content clips behind it as designed); Edit job sheet PASS (Save changes clear of the gesture bar, no double void); Change-office (ReassignOfficeSheet) PASS (Pick an office with the same clean inset). All four show the buttons sitting one comfortable inset above the edge, no glue and no double bottom padding. The fifth consumer (SetupWizard/WizardStepFrame) is UNREACHABLE on device — setup already completed, no Setup entry survives anywhere (Home / Account / Attendance) — verified only by the same code read (no footer-local bottom padding in any pre-existing consumer), so the four pass-fail verdicts cover the wrapper's one-risk double-padding directly through three distinct detent shapes.
- [x] [Review][Patch] BE `offices` tallies break their own full-tenant contract when an office filter is applied [fenzit-be/src/attendance/dashboard.ts:98-142] — the filter `continue` runs before the per-office accumulation, so with `officeId` set every other office reports 0/0; move accumulation ahead of the filter.  → DONE — accumulation hoisted above the filter `continue` in `dashboard.ts`; per-office tallies are always full-tenant-scope, the filter shapes only tiles/flags; BE suites + journey e2e green.
- [x] [Review][Patch] BE boundary pins broken by `offices` [fenzit-be/src/attendance/dashboard-response.model.spec.ts:14,46 + test/attendance-reads.e2e-spec.ts:239] — the model spec now fails `tsc` (fixtures lack `offices`), the e2e key-set pin excludes `offices`; fix the pins and assert the registry row shape + filtered narrowing + full-scope tallies + narrowed flags in the real-DB integration probe.  → DONE — model-spec fixtures carry `offices`; the key-set pin includes it; the real-DB probe asserts the registry row shape, filtered narrowing, full-scope tallies per office, and narrowed flags.
- [x] [Review][Patch] The D8 mirror is not character-for-character [fenzo-app/src/features/attendance/notifications/notificationEvents.ts:122] — FE uses a straight apostrophe `office's`, the BE literal uses U+2019 `office’s` (BE at notification-events.ts:197 is the source); align FE and pin the full literal, not a prefix.  → DONE — FE literal aligned to the BE's U+2019 `office’s`; the mirror test pins the full literal.
- [x] [Review][Patch] PresentCard clamps the bar but not the caption/a11y label [fenzo-app/src/features/attendance/dashboard/PresentCard.tsx:34-38] — an inconsistent envelope can read "200% workforce present today"; clamp the shown share for caption + accessibilityLabel (the model deliberately exposes 200 — clamping belongs here, one layer up).  → DONE — caption + accessibilityLabel render the clamped share; the model still exposes the unclamped pct deliberately (clamping is this component's job).
- [x] [Review][Patch] FlagListSheet rows are unreachable when the list overflows its auto detent [fenzo-app/src/features/attendance/dashboard/FlagListSheet.tsx:42-57] — the sibling OfficeFilterSheet already established the scrollable idiom with the "list is unbounded" rationale; apply it here too.  → DONE — body made scrollable (the OfficeFilterSheet idiom) with the unbounded-list rationale in its docblock.
- [x] [Review][Patch] OfficeFilterSheet effect contradicts its own comment [fenzo-app/src/features/attendance/dashboard/OfficeFilterSheet.tsx:86-93] — `stats` IS in the deps array the comment says it excludes; a stats identity change from a refetch while the sheet is open re-seeds the draft and discards the owner's un-applied pick; honour the comment (remove `stats`) and re-check the disable is still needed.  → DONE — effect deps are now `[visible, selected, loadFallback]` with `stats` deliberately OUT; the comment is true; re-open no longer re-seeds an un-applied draft mid-refetch.
- [x] [Review][Patch] A failed post-pick refetch leaves the selector showing the picked office over the previous unfiltered numbers [fenzo-app/src/features/attendance/dashboard/AttendanceDashboardScreen.tsx:321-327 + catch path] — revert `pickedOffice`/`officeIdRef` on load failure so field and numbers agree (the last-good discipline applied to the filter).  → DONE — the load catch reverts `officeIdRef`/`pickedNameRef`/`pickedOffice` to `lastGoodPickRef` so field and numbers agree.
- [x] [Review][Patch] The Skeleton's two loops never stop on unmount [fenzo-app/src/components/ui/Skeleton.tsx:33-61] — add `stop()` in effect cleanups (the suite's own docblock documents the Jest-worker crash this invites).  → DONE — `stop()` runs in both effect cleanups.
- [x] [Review][Patch] Apply's dead-office draft commits an empty label [fenzo-app/src/features/attendance/dashboard/OfficeFilterSheet.tsx:96-104] — when the draft id matches no row (office removed mid-flight), the commit resolves `name: ''` and the selector renders blank; bail out instead.  → DONE — `applyDraft` bails on a dead draft id (`if (!row) return;`).
- [x] [Review][Patch] `flagRowDate` accepts out-of-range components [fenzo-app/src/features/attendance/dashboard/dashboardModel.ts:139-145] — month 00/13-99 or day 00/32+, 32-99 rolls via `Date.UTC` (wrong weekday, blank month name, double space); reject ranges the format check alone misses and render raw.  → DONE — out-of-range month (00/13+) or day (00/32+) components are rejected and the raw string renders.
- [x] [Review][Patch] `officeId` may be double-encoded [fenzo-app/src/services/resources/attendanceDashboard.ts] — `encodeURIComponent` before an apiClient whose params the client itself serialises (paramsSerializer); emit the raw id and let the client encode once (also assert the emitted URL in the service test).  → DONE — the service passes the RAW id; apiClient's paramsSerializer encodes once; the service test asserts the emitted URL.
- [x] [Review][Patch] DashboardHeader's dead `minHeight` [fenzo-app/src/features/attendance/dashboard/DashboardHeader.tsx] — `minHeight: touch.min` is dead under fixed `height: CHIP (44)`; remove it.  → DONE — removed.
- [x] [Review][Patch] The screen's press-list assertion cannot fail if tiles became pressable [fenzo-app/src/features/attendance/dashboard/AttendanceDashboardScreen.test.tsx:236-238] — `arrayContaining` is a subset test; pin the exact press set per posture (tiles + strips + chrome).  → DONE — the exact sorted press set pinned per posture (a regression can no longer pass silently).
- [x] [Review][Patch] The NotificationsScreen `dashboard` tap branch is untested [fenzo-app/src/features/notifications/NotificationsScreen.tsx:286-292] — add a screen-level test: owner card marks its unread ids read and navigates to AttendanceDashboard; a missing-negative (the seam path unchanged) rides in the same change.  → DONE — `NotificationsScreen.dashboard-tap.test.tsx`: owner card marks its unread id read and navigates to AttendanceDashboard; the missing-negative (guard bypass) rides in the same file.
- [x] [Review][Patch] The AppState-active refetch branch is unreached by any test [fenzo-app/src/features/attendance/dashboard/AttendanceDashboardScreen.tsx:179-187] — add: focused + `active` → exactly one fetch; unfocused → none.  → DONE — AppState describe: focused + `active` → EXACTLY one more fetch; unfocused → none; `background`/`inactive` → none.
- [x] [Review][Patch] Five presentational components carry unpinned rules [fenzo-app/src/features/attendance/dashboard/KpiTile.tsx, FlagStrip.tsx, DashboardHeader.tsx, PresentCard.tsx, WorkspaceSelector.tsx] — e.g. the fake-location CRITICAL chip appears ONLY on the fake strip, the pct pill's colour pairing, disabled/refreshing chip states; add the per-component tests.  → DONE — per-component suites for KpiTile (non-interactive, pct pill only when set), FlagStrip (CRITICAL only when critical), DashboardHeader (disabled/busy/spinner swap, back), PresentCard (clamp everywhere, a11y pairing on all carriers), WorkspaceSelector (count-driven pill, singular at 1).
- [x] [Review][Patch] The attendance journey e2e suite is not extended — the standing rule (every attendance story spec extends the permanent real-DB journey suite) is unmet; add the dashboard step (owner reads tiles; office filter narrows both tiles and flags; DB asserts).  → DONE — the journey suite's first leg is the dashboard step (owner reads tiles; the office filter narrows tiles AND flags; DB asserts after each API step; real routes, real DB, FK-safe cleanup).
- [x] [Review][Patch] `notCheckedInMessage` renders count 0 [fenzo-app/src/features/notifications/notificationEventRegistry.ts:178-186] — "0 haven't checked in at X." is nonsensical copy a drifted payload can mint; treat count < 1 as drift → null (honest minimal card).  → DONE — count < 1 is treated as drift → null (honest minimal card).
- [x] [Review][Patch] The frozen-spec record needs its mid-build amendments [this file §2/§3/§4/§9] — D3's shape now includes `offices` + the BE-first order (§9 has it; §2/§3 do not); D2's verbatim claim vs the sheen sweep + `height` prop; D4's neutrality vs the mock's hue family; D9 vs manualRefresh shimmer; D7/D10's offices-fetch-at-load-when-fallback; §3's copy additions; §9's stale gate line; D5's wrong fact (`DAY_STATUS_VISUALS.checkout_missing`, not `.checkoutMissing`); D6's one-line detail merge + Files >300 (split both over-limit files in this same change).  → DONE — §2 (D2 sheen/height, D3 raw-id + `offices` + BE-first order, D4 hue supersession, D5 `.checkout_missing`, D6 one-line detail merge + scrollable), D7/D10's fallback-at-load, D9's manual-pull shimmer, §3's as-built copy additions, §4's split files (see next two notes), §9 re-records below. The two >300 files split VERBATIM in this change: AttendanceDashboardScreen → `useDashboardData.ts` (277-line screen), OfficeFilterSheet → `OfficeCard.tsx` (295-line sheet); zero behaviour change, suites prove it.
- [x] [Review][Patch] `dataRef.current = data` is written during render [fenzo-app/src/features/attendance/dashboard/AttendanceDashboardScreen.tsx:88] — assign in an effect instead (concurrent-mode tearing hazard; all reads happen post-commit).  → DONE — moved into an sync effect in `useDashboardData.ts` (comment states the tearing hazard; reads stay post-commit).
- [x] [Review][Patch] New files lack trailing newlines [fenzo-app dashboard components + tests] — restore them (house files end with one; keeps future diffs clean).  → DONE — restored.
- [x] [Review][Patch] Dead/cosmetic cleanups — Sheet.tsx:96 `?? {…0}` dead guard (the hook throws without a provider; fix the comment); KpiTile hardcodes `999` twice instead of `radius.pill`; test-file dead weight (`void todayButton`, `void shown`, the redundant `not.toBeNaN` after `toBe(158)`, `expect(hasA11yLabel(...))` wrappers around self-asserting helpers); FlagListSheet row key's `,${index}` suffix.  → DONE with an HONEST CORRECTION to the guard claim: the `?? {…0}` guard was NOT dead — it protected provider-less mounts from `jest.resetAllMocks()` wiping the safe-area library mock's `jest.fn` hook implementations (proven by an error-boundary probe; every suite that resets mocks and renders a Sheet went red without it). The review's component semantics are kept (no production fallback); the fix landed in the TOOLING — `jest.setup.js` re-exposes `useSafeAreaInsets`/`useSafeAreaFrame` as plain functions (not wiped by reset) reading the real contexts with the zero fallback. KpiTile's `999` → `radius.pill`, the test-file dead weight (`void shown`, `void todayButton`, the redundant `not.toBeNaN`, the self-asserting-helper wrappers), and the FlagListSheet row-key `,${index}` suffix also cleaned.
- [x] [Review][Defer] A 403 on the owner read renders the generic "Check your connection" copy [fenzo-app/src/features/attendance/dashboard/LoadErrorRetry.tsx] — deferred, pre-existing house idiom (no FE screen distinguishes 4xx copy today); revisit if owner flows start failing auth distinctly.
