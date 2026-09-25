# Frontend review — Attendance & Leave PRD (2026-09-25)

Reviewer lens: React Native / UX engineer, checked against the real `fenzo-app` code (RN 0.87.1, bare RN CLI — not Expo, New Architecture on, Hermes, iOS min 15.1, Android minSdk 24 / target 36).
Scope: `prd.md`, `addendum.md` §A + §B2, `.memlog.md`. No PRD, addendum or code was changed.

**Verdict: FEASIBLE WITH CHANGES.** The frontend can build this. But the §B2 reuse plan has several claims that are wrong or incomplete against the code. The biggest ones: technician realtime is also blocked on the client, attendance notifications would be dropped from the shared inbox, iOS does give a mock signal, and the current location helper uses weak accuracy defaults. Fix the 6 high findings in the PRD/addendum before architecture starts. The medium findings can be fixed in the UX spec or architecture.

Counts: critical 0 · high 6 · medium 15 · low 7

Paths below are relative to `workspace/core/frontend/fenzo-app/`.

---

## High

### H1. Technician realtime is blocked on the client too, not only on the backend
- **PRD location:** FR-27; addendum §A6, §B1 ("`GET /auth/realtime-token` → allow technicians"), §B2 ("role-agnostic realtime bridge").
- **Evidence:**
  - `src/services/realtimeToken.ts:45-57, 70-73`: `isCurrentUserTechnician()` decodes the JWT and returns `null` for technicians **before** any call. So even after the backend opens the endpoint, technicians never get a token.
  - `src/features/notifications/OwnerRealtimeBridge.tsx:20-30`: owner-only allowlist. `src/App.tsx:58-65`: the technician branch mounts no bridge.
  - `src/features/notifications/useOwnerNotifications.ts:131-167`: the handler is job-specific. It force-refetches `loadJobs` + `loadMyProfile` (the heavy `/users/me`) and raises a job banner.
  - `src/components/StatusBanner.tsx:26-29`: typed to `OwnerNotificationBanner` (technician name / job number / step chips).
  - `src/services/supabaseRealtime.ts:68-97`: names are owner-specific (`getOwnerChannel`, `ownerNotificationsTopic`), but the topic format is already role-neutral.
- **Fix (addendum §B2 "Generalise"):** list these explicitly. (a) Remove the technician short-circuit in `realtimeToken.ts`. (b) Extract a role-neutral `useNotificationStream({ onEvent })` hook that keeps the AppState gate, topic guard and reset-registry teardown. Owner and technician bridges become thin callers. (c) Mount a `TechnicianRealtimeBridge` in the technician branch of `App.tsx`. (d) Make `StatusBanner` generic, or state that technician events show no toast in v1 and only update the badge. Say which one.

### H2. Attendance/leave notifications would be invisible in the shared inbox; the owner banner would misfire
- **PRD location:** FR-22 ("Tapping a Notification opens the related leave or day"), FR-27 ("Existing Owner job and report notifications look and behave exactly as before"), addendum §B2 "event-type registry".
- **Evidence:**
  - `src/features/notifications/notificationCardModel.ts:147`: `if (n.jobId === null) continue;` drops every job-less row.
  - `src/features/notifications/reportNotificationModel.ts:46, 87`: only `report_ready`/`report_failed` get cards. So a `leave_applied` row (jobId null) shows **nowhere**, but `GET /notifications/unread-count` still counts it. The badge would say "1" over an empty list, and "Mark all read" would be the only way to clear it.
  - `src/features/notifications/useOwnerNotifications.ts:144-166`: every event that is not a report is treated as a job step. A `leave_applied` broadcast would show the "Job status updated" fallback banner (`notificationBannerModel.ts:24`) and refetch jobs + `/users/me`.
  - `src/services/resources/notifications.ts:27-44`: `ApiNotification` has no `entityType`/`entityId`.
- **Fix:** in §B2, make the registry a concrete contract. `eventType → { cardKind, title/body from payload, deepLink(entity), storesToRefetch, showsToast, filterBucket }`. The default for an **unknown** event type is a generic card (never dropped) and no job refetch. Attendance cards appear under "All" only (same as reports). Add `entityType`/`entityId` to `ApiNotification`. Add an acceptance line to FR-27: "badge count always equals the number of unread rows the list can show."

### H3. The claim "no fake-GPS signal on iOS" is wrong for this app's iOS floor
- **PRD location:** FR-7 (iOS bullet), §7.2, addendum §A3, memlog "iOS relies on accuracy + radius only".
- **Evidence:**
  - `node_modules/react-native-nitro-geolocation/ios/CLLocation+GeolocationMetadata.swift:5-10`: `mocked` = `sourceInformation?.isSimulatedBySoftware` (iOS 15+).
  - `ios/Podfile` / `project.pbxproj:269`: deployment target 15.1, so every supported iPhone reports it.
  - `ios/IOSGeolocationConversions.swift:45`: it is included in the foreground `getCurrentPosition` response.
- **Fix:** change A3 to "Android: `isMock`/`isFromMockProvider`. iOS 15+: `isSimulatedBySoftware` (catches Xcode/software simulation and some spoofing tools; not every jailbreak tweak)." Send `mocked` from both platforms and apply the same server rule. Update §7.2 to "iOS signal is partial". The rooted/jailbroken exclusion stays.

### H4. The current location helper's defaults are unfit for a 100 m, anti-spoof check-in
- **PRD location:** FR-7 (accuracy, fake GPS, "device clock is never trusted"), addendum §A1 ("Reuse the permission helper only") vs §B2 ("generalise geolocation.ts").
- **Evidence:**
  - `src/features/technicianApp/geolocation.ts:84`: calls the **compat** `Geolocation.getCurrentPosition` with **no options**.
  - Compat Android `GetCurrentPosition.kt:49-53` + `:338`: default `maximumAge = +Infinity`. It returns the **last known fix of any age** straight away. A fix cached at the office yesterday could "check in" from home.
  - Accuracy default is `BALANCED` on Android (`AndroidAccuracy.kt:29`) and `kCLLocationAccuracyHundredMeters` on iOS (`IOSGeolocationOptions.swift:51-54`). That is right at the 100 m rejection line, so many honest check-ins would fail (this hurts SM-C1).
  - `geolocation.ts:87-96`: drops `mocked`, `provider` and `timestamp`.
  - `geolocation.ts:32-47`: requests only `ACCESS_FINE_LOCATION`. On Android 12+, if the user picks "Approximate", this is reported as `denied`. iOS "Precise: off" is not detected. `getAccuracyAuthorization()` exists (`src/api/getAccuracyAuthorization.ts`) but is unused.
  - The helper does not tell "denied" apart from "blocked / never ask again", and there is no open-Settings path.
- **Fix:** add a "Location capture contract" to FR-7 / addendum §B2. Use the modern `getCurrentPosition` with `{ accuracy: { android: 'high', ios: 'best' }, maximumAge: 0, timeout: ~20s }`. Send `mocked`, `provider`, `accuracy` and the fix `timestamp` (the server rejects a fix older than N s relative to receipt). Detect reduced/approximate accuracy with its own copy ("Turn on Precise location for Fenzit"). On iOS, optionally use `requestTemporaryFullAccuracy`, which needs a new `NSLocationTemporaryUsageDescriptionDictionary` in `Info.plist`. Tell `blocked` apart and offer `Linking.openSettings()`. Check `hasServicesEnabled()` and, on Android, `requestLocationSettings()`. **Do not** change the job flow's compat call (NFR-12). The new service is used only by attendance.

### H5. One `attendanceEnrolled` boolean from `/users/me` cannot drive the visibility rules
- **PRD location:** FR-1 ("Until the wizard is completed, no Employee sees any attendance UI"), FR-3 (previously tracked employee keeps read-only history), addendum §B1/§B2 (`attendanceEnabled` + `attendanceEnrolled`, "technician → 4th tab shown only when enrolled").
- **Evidence:**
  - `src/navigation/TechnicianTabs.tsx:19-36`: static 3 tabs.
  - `src/features/profile/useMyProfile.ts`: the profile is loaded once and refetched only on focus by `TodayScreen`/`ProfileScreen` (throttled by `FOCUS_REFRESH_TTL_MS`). There is no realtime profile refresh for technicians.
  - `src/services/resources/users.ts:133-163`: `MyProfile` has no attendance fields.
- **Problems:** (a) a disabled employee who still has history needs the tab (FR-3) but is "not enrolled". (b) If the owner enables someone mid-session, the tab appears only after a later profile refetch. (c) While the profile is loading (`profile === null`), the tab bar would render 3 tabs and then jump to 4. (d) If the tab is removed while the user is on it, React Navigation silently resets the route.
- **Fix:** expose a tri-state `attendanceAccess: 'none' | 'active' | 'history_only'` (plus `attendanceOnboarded: boolean` for FR-4) instead of one boolean. Hide the tab until the profile has loaded (no flicker). Refetch the profile on app resume and when an attendance notification arrives, and say this in the addendum. `history_only` shows the tab with check-in hidden and a "Attendance tracking is off for you" note.

### H6. FR-9 auto-cancels approved leave on check-in without asking the employee
- **PRD location:** FR-9, UJ-3.
- **Evidence:** a UX gap, not code. One tap on "Check in" on a leave day (for example, stopping by the office to pick up something) would quietly destroy approved leave and notify the owner.
- **Fix:** add a consequence: "When today is an approved full-day Leave, Check in first shows a confirmation: 'You're on leave today. Checking in will cancel today's leave and notify {owner}.' [Cancel] [Check in anyway]." The server rule stays the same; the client passes an explicit `confirmLeaveCancel: true` so a stale client cannot cancel by accident. Do the same (lighter) for check-in on a Weekly off/Holiday ("This will count as worked on holiday").

---

## Medium

### M1. Map library: feasible, but the addendum's key/provider plan is heavier than needed
- **PRD location:** FR-5, §7.1, addendum §A2, §B2 "Office pin picker".
- **Evidence:** `package.json` has no map library. This is a bare RN CLI app (`app.json`, `ios/Podfile`, no Expo), with `newArchEnabled=true` (`android/gradle.properties:35`). react-native-maps README (Context7): Fabric supported, v1.26.1+ needs RN ≥ 0.81.1, so it fits RN 0.87. `CLAUDE.md` requires New-Arch-first libraries.
- **Fix:** name `react-native-maps` ≥ 1.26.1 in the addendum. Use **Apple Maps on iOS (default provider, no key, no GoogleMaps pod, no AppDelegate change)** and the Google provider on Android only. `Circle` and draggable `Marker` work on both. The Android key goes in via `manifestPlaceholders` from `local.properties`/CI, never hard-coded (this repo already commits its keystore; don't add a key the same way). Restrict the key to `com.fenzitapp` + the SHA-1 of **each** signing keystore (debug/metroDebug and `fenzit-release.keystore`), or Android debug builds show a blank map. Record it as a native rebuild (pod install + gradle).

### M2. Map/sheet architecture and address-picker reuse details
- **PRD location:** FR-5 (three pin paths "ending on the same map screen", "map fails to load" fallback).
- **Evidence:**
  - `src/features/addressPicker/AddressPickerSheet.tsx:1-20`: pushing a stack route over a presented native TrueSheet silently dismisses the sheet (a known device bug). So the map must be a full-screen stack route, and address search opens as a Sheet **from** the map screen, never the other way round.
  - `AddressPickerSheet.tsx:30-36` / `ManualAddressForm`: the no-results fallback is manual entry **without coordinates**. It must be hidden for office setup.
  - react-native-maps has `onMapReady` but no "failed" event. Offline Google/Apple maps show grey tiles with a working pin.
- **Fix:** FR-5: "Map picker is a full-screen route; address search is a sheet on it; manual address entry is not offered for Offices." Detect "map unavailable" with an `onMapReady` timeout plus network error, and still allow save using the current location or search result coordinates (show the coordinates + radius as text). Prefer a **fixed centre pin with the map moving under it** over dragging a small marker. It is easier to use with one thumb and gives larger touch targets; the circle follows the centre.

### M3. Permission copy and the reuse rule contradict each other
- **PRD location:** NFR-12 ("location permission helper … reused as-is"; "only allowed change … without changing its behaviour"), addendum §A1 ("Reuse the permission helper only"), §B2 ("generalise … neutral permission copy (iOS/Android strings too)"; "Do not touch: LocationCaptureScreen").
- **Evidence:**
  - `src/features/technicianApp/geolocation.ts:16-27`: copy says "verify step completion".
  - `ios/FenzitApp/Info.plist:44-45`: "Fenzit uses your location to record where you complete technician jobs." The **owner** would see this when tapping "Use my current location" for an office. App Store review also expects the purpose string to cover attendance.
  - `LocationCaptureScreen.tsx:17`: imports `./geolocation`, so moving the file means touching that line.
- **Fix:** state one rule. The attendance location service is **new** (`services/location`). `technicianApp/geolocation.ts` stays as-is for jobs (or becomes a re-export shim; a one-line import change in `LocationCaptureScreen` counts as "no behaviour change"). `NSLocationWhenInUseUsageDescription` changes to neutral copy covering jobs, office setup and attendance (it's app-wide, and this is an accepted visible change). The Android runtime-dialog copy for attendance is set on its own.

### M4. GPS acquisition UX is not specified
- **PRD location:** FR-7, NFR-8, SM-C1 ("UX fixes (better GPS guidance)").
- **Evidence:** the only precedent is `LocationCaptureScreen.tsx:105-131`: one spinner, a single 15 s shot, and a generic error.
- **Fix:** add FR-7 consequences. (a) A "Getting a precise location…" state with elapsed time. (b) The client watches for up to ~20 s and submits the best fix as soon as it is ≤ 100 m, or shows "Location not accurate enough" with tips (step outside / near a window, turn on Wi-Fi) and Retry, **without** calling the server (the server still re-checks). (c) Cancel is always available. (d) The button uses `<Button loading>` (DS rule) during capture + submit, and repeat taps are blocked.

### M5. Offline detection: NetInfo is a new native dependency, and a request-level approach already exists
- **PRD location:** FR-7 ("Offline → blocked in the app"), NFR-8, addendum §B2 "Offline detection (NetInfo) + banner".
- **Evidence:** `@react-native-community/netinfo` is not in `package.json`. The connectivity UX story (`_bmad-output/implementation-artifacts/4-3-connectivity-ux.md`) was deferred. `src/services/api/apiError.ts:24, 67-105` already maps offline/DNS/timeout to `status: 0` with separate timeout handling. The backend idempotency interceptor caches **success only** (`fenzit-be/src/common/interceptors/idempotency.interceptor.ts:101-118`), so a retry with the same key after a timeout safely replays a check-in that already landed.
- **Fix:** make the request outcome the source of truth. `status 0` → "You're offline. Check in needs internet" + Retry that reuses the **same** idempotency key (LocationCaptureScreen `keyRef` pattern, `:28, 52`). If NetInfo is added for a pre-emptive banner, mark it as a native rebuild and a hint only (captive portals report "connected"). A timeout must say "We couldn't confirm your check-in. Retry", never "failed".

### M6. In-app-only reminders will rarely be seen, and the metrics depend on them
- **PRD location:** FR-23, SM-2, SM-4, §7.2 (push deferred).
- **Evidence:** no push or local-notification library in `package.json`. The realtime socket is foreground-only (`useOwnerNotifications.ts:9-13`).
- **Fix:** state clearly in FR-23 that a reminder is visible only on the next app open, and that SM-2/SM-4 targets assume this. Also add: the Attendance tab / Today screen shows an in-screen nudge card ("You haven't checked in — office started at 10:00 AM") computed from server "today" state, so the reminder has value even without the inbox. Optionally note on-device scheduled local notifications (for example Notifee, native dep, Android 13 `POST_NOTIFICATIONS`) as a v1.1 bridge before server push.

### M7. The 50 × 31 month grid is not phone-friendly as specified
- **PRD location:** FR-25, UJ-4, NFR-7 (monthly view ≤ 3 s for 50 employees).
- **Evidence:** DS: `layout.contentMax` 480, touch ≥ 44 px (`src/theme/DESIGN_SYSTEM.md` "Touch targets"). 31 × 44 px ≈ 1364 px wide × 50 rows = 1550 tappable cells, which needs 2-axis scroll with a sticky name column and date header. No FlashList or grid library is present; FlatList + nested horizontal ScrollView sync is fragile. A screen reader over 1550 cells is not usable.
- **Fix:** in FR-25, make the default owner month view a **virtualised per-employee summary list** (name, days worked, late, leave, absent, flags). Tap → that employee's **month calendar** (7-column grid, the same component as the employee self view in FR-26). Tap a day → day detail sheet. Keep the full matrix as optional ("Grid" SegmentedControl view, horizontal scroll, compact colour + letter cells, not individually focusable for a11y; row-level label instead). One API call returns the month matrix; the client never derives statuses.

### M8. The design system has no vocabulary or colours for 10 day statuses + 5 flags
- **PRD location:** FR-10 (10 statuses), FR-7/8/13/21 flags (Late, Early checkout, Leave pending, Fake location attempt, Corrected by owner).
- **Evidence:** `src/theme/colors.ts:121-155` has only `done | progress | scheduled | cancelled | neutral`. `src/components/ui/Badge.tsx:2-5` and `CLAUDE.md` state a **fixed** job-status vocabulary, "no synonyms".
- **Fix:** add to the PRD (or push to the UX spec) a mapping table: status → token → short label → letter/icon for the calendar cell. Allow a separate `attendanceStatus` token group (tokens first, per DS rules), so the job Badge vocabulary is not reused for attendance. Never colour-only: every cell carries a letter/icon, plus a legend.

### M9. Time and date display do not follow the DS, and timezone math should not live on the client
- **PRD location:** UJ-1/UJ-2 copy ("10:00", "10:22", "18:22", "10:00–18:00"), NFR-5, addendum §B2 ("`istDate` → timezone-parameterised date math").
- **Evidence:** DS: "12-hour times ('10:30 AM')" (`DESIGN_SYSTEM.md` Content & voice). `src/utils/istDate.ts:1-22` is a fixed +5:30 offset because Hermes Intl is incomplete. `src/features/newJob/components/DateTimeFields.tsx:31-38` formats with **device-local** `getDate()`/`getHours()`.
- **Fix:** change PRD copy to 12-hour ("10:22 AM", "10:00 AM – 6:00 PM", "Late by 22 min", "8 h 8 min"). In the addendum: the API returns tenant-local `date` (`YYYY-MM-DD`) and local time strings for every attendance record, plus `today`/`now` in the tenant timezone. Office times are sent and stored as `HH:mm` strings, not `Date`. The client does **no** timezone day-boundary math. Drop "timezone-parameterised istDate" from §B2 (not needed while all tenants are IST, and risky on Hermes).

### M10. Wrong or missing items in the §B2 reuse list
- **PRD location:** addendum §B2 "Reuse as-is" column.
- **Evidence:**
  - `DateTimeFields` is not in `components/ui`. It is at `src/features/newJob/components/DateTimeFields.tsx`, edits one combined `Date`, and has no time-only, date-range or month picker mode.
  - `TechnicianPicker` exists twice (`src/components/TechnicianPicker.tsx`, `src/features/newJob/components/TechnicianPicker.tsx`). Both are **single-select** with toggle-to-clear (`components/TechnicianPicker.tsx:13-16`). The wizard step 5 needs multi-select + a per-employee office.
  - `MultiSelect` uses RN `Modal`, not the native `Sheet` (`src/components/ui/MultiSelect.tsx:11, 105`), which is inconsistent with the DS sheet rule.
  - `ReportSkeleton` is hard-coded to 3 × 80 px rows (`src/features/reports/components/ReportSkeleton.tsx:8-10`).
- **Fix:** move `DateTimeFields` to "Generalise" (lift to `components/ui`, add `mode: 'date' | 'time'`; new `DateRangeField` and `MonthSwitcher`). Replace TechnicianPicker reuse with a new "EmployeeSelectList" (multi-select rows + office Select per row, virtualised). `Skeleton` should take shape/count props. Add "Bell button with badge" as a shared extraction (see L2).

### M11. The wizard shell and "resume later" do not fit the AuthFlow pattern
- **PRD location:** FR-1 (resume [ASSUMPTION]), addendum §B2 ("`AuthFlow` step pattern + `StepIndicator` → shared wizard shell").
- **Evidence:** `src/features/auth/AuthFlow.tsx:57-75`: steps are in-memory `useState`, lost on unmount. The office map picker (M2) must be a pushed route, which a single-component step switcher cannot host cleanly. `StepIndicator.tsx` renders numbered 36 px dots; 5 steps fit, but the a11y label sits only on the row.
- **Fix:** the wizard is a native-stack flow (one route per step), and its progress is **saved on the server** (offices, rules, holidays are real records created as you go; module `enabled` flips only at "Finish"). Resume = read server state and jump to the first incomplete step. Say so in FR-1 and drop MMKV drafts. Reuse only `StepIndicator` (visuals), not AuthFlow.

### M12. "Make NotificationsScreen role-aware" needs a concrete list
- **PRD location:** FR-27, addendum §B2 "Build new: Technician entry to the existing notifications screen".
- **Evidence:**
  - `src/features/notifications/NotificationsScreen.tsx:67-70`: props typed to the owner `RootStackParamList` + `MainTabParamList`.
  - `:302-311`: empty state copy "Updates from your technicians — job arrivals…" and CTA "Go to jobs" → owner `Jobs` tab (does not exist for technicians).
  - `:249`: All/Active/Completed chips are job buckets.
  - `:111-130`: taps route only to `Reports`/`JobDetail`.
  - `src/navigation/types.ts:87, 127-131`: "Owner-only notification history"; the global `RootParamList` augmentation is owner-only; `TechnicianRootStackParamList` (`:118-125`) has no Notifications route.
  - `src/navigation/navigationRef.ts:13`: typed to the owner list but shared by both containers.
- **Fix:** add to §B2: register `Notifications` in `TechnicianRootNavigator`. Pass role-specific empty copy/CTA (technician: "No notifications yet", no CTA). Hide the filter chips for technicians. Route taps through the registry (H2). Type navigation per role (no casts). FR-27 acceptance: "technician empty state has no job CTA".

### M13. The owner entry point contradicts itself before enablement
- **PRD location:** FR-3 ("The Owner sees the Attendance entry point once the module is enabled") vs UJ-1 ("Attendance is not enabled yet … opens the Attendance entry point and starts the setup wizard"); addendum §B2 ("owner → MoreScreen tile + Home card").
- **Evidence:** `src/features/more/MoreScreen.tsx:158-175`: the tile row is a fixed 2-up (Technicians, Notifications); a third tile breaks the grid. Reports/Customers use `MoreRow` (`:177-192`).
- **Fix:** FR-3 → "The Owner always sees the Attendance entry point. Before setup it opens an intro + 'Set up attendance'; after, the dashboard." Use a `MoreRow` ("Attendance", subtitle "Not set up" / "5 tracked · 3 checked in"). The Home card shows only after setup, or as a dismissible promo before. Note that the Home change is in a job screen but is additive.

### M14. How the owner dashboard stays fresh is undefined
- **PRD location:** UJ-2 ("the owner's dashboard shows the same"), FR-24.
- **Evidence:** check-in/out creates no owner Notification (FR-22 table), so no broadcast reaches the owner. The owner bridge refetches only jobs/profile/reports (`useOwnerNotifications.ts:144-166`).
- **Fix:** FR-24: "Dashboard refreshes on focus, on pull-to-refresh and on app resume (`useNow` resync precedent, `src/hooks/useNow.ts`), and shows 'Updated {time}'." Real-time live check-in updates are out of v1 (or add a silent `attendance_changed` broadcast that is not shown in the inbox, which is a backend call to make).

### M15. Missing screen states and server-computed previews
- **PRD location:** FR-4, FR-7/8, FR-12, FR-26, NFR-8.
- **Evidence:** the PRD lists only "offline", "accuracy" and "distance" copy. `features/technicianApp/TodayScreen.tsx:76-110` is the pattern to follow (first-load spinner, error+retry, stale banner).
- **Fix:** add a check-in screen state table: not-yet-onboarded · permission undetermined / denied / blocked · location services off · precise off · acquiring · poor accuracy · too far (server distance + office name) · mocked · offline · timeout-unknown-outcome · server error · already checked in (other device) · checked in (time + Late) · checked out (hours + Early) · leave day (H6) · half-day leave · weekly off/holiday (confirm) · midnight rollover while open (refetch "today" on resume/focus). Also, FR-12 "app shows the number of Working days" must come from a server **preview** endpoint (NFR-2; the client does not know effective-dated weekly offs/holidays). Add it to §B1 and the loading/error state for the preview.

---

## Low

### L1. The live "you are X m away" hint conflicts with NFR-11 and with the server value
- **PRD location:** addendum §A0, §B2 (`distanceUtils` live hint), NFR-11 ("Location captured only at the moment of Check-in/Check-out").
- **Evidence:** `src/utils/distanceUtils.ts:37-43`: `formatDistance` appends " away" and rounds to 10 m, so it doesn't fit the PRD copy "You are 600 m from Andheri office". A live hint needs continuous foreground watching.
- **Fix:** show the distance only from the server's rejection response (the server's number is the truth). Use `haversineMetres` at most for a one-off pre-check after capture. Add a `formatDistanceFrom(office)` variant, or render server copy.

### L2. Technician bell placement is not specified; bell badge code is duplicated
- **PRD location:** FR-27 ("bell and badge visible to every technician").
- **Evidence:** `src/features/technicianApp/TodayScreen.tsx:76-78`: the header has only a greeting. Bell + badge logic is copied in `src/features/jobs/JobsScreen.tsx:55, 282-287` and `src/components/HomeHeader.tsx:68-126`.
- **Fix:** say "bell in the Today and Attendance tab headers", and extract a shared `NotificationBell` (99+ cap, a11y label "Notifications, 3 unread"). The badge loads on technician app start and on resume.

### L3. The tab icon map needs an entry
- **Evidence:** `src/navigation/TabBar.tsx:30-50`: an unknown route falls back to the Home icon. A 4th technician tab means adding `Attendance` to `ICONS` and to `TechnicianTabParamList` (`src/navigation/types.ts:30-34`).
- **Fix:** list it in §B2 "Generalise" (trivial).

### L4. Deep-link targets can go stale
- **PRD location:** FR-22 ("Tapping a Notification opens the related leave or day").
- **Evidence:** leave requests split/cancel/revoke; an employee may become untracked (H5).
- **Fix:** define routes `LeaveDetail { leaveId }` and `AttendanceDay { employeeId?, date }`, with a "This request has changed" / "No longer available" state instead of an error screen. For `history_only` users, open read-only.

### L5. The idempotency key rule for check-in should be written down
- **Evidence:** `src/utils/idempotency.ts:1-15`. `LocationCaptureScreen.tsx:28, 52, 61` mints one key per user action and reuses it on retry. The backend caches success only, with no body hash.
- **Fix:** addendum: "one key per Check-in/Check-out tap; retries of the same attempt (timeout/offline) reuse it; a new tap after a rejection mints a new key."

### L6. Nitro devtools mock positions bypass the mock flag in dev
- **Evidence:** `node_modules/react-native-nitro-geolocation/src/api/getCurrentPosition.ts:36-40`, `src/devtools/index.ts:27-29`: `__DEV__`-only devtools positions return without the native `mocked` field.
- **Fix:** add a QA note. Test fake-GPS rejection on a release/metroDebug build with a real mock-location app, not with devtools.

### L7. Accessibility requirements are thin
- **PRD location:** NFR-8 (no a11y NFR).
- **Fix:** add an NFR. Calendar cells have labels ("14 Sep, Present, late by 22 minutes"). Check-in success/failure is announced (`AccessibilityInfo.announceForAccessibility`; precedent in `AddressPickerSheet.tsx` live-region). Status is never colour-only. Every action ≥ 44 px. Dynamic type does not clip the summary numbers (tabular figures, DS). Sentence-case copy, no emoji.

---

## Checked and OK
- `apiClient`, `pagination`, `idempotency`, `resetRegistry`, `useSyncExternalStore` store pattern: reusable as stated.
- `places` endpoints + `useAddressAutosuggest`: reusable for the office search (with M2 caveats).
- `react-native-nitro-geolocation` 1.4.3 exposes `mocked`/`provider`/`timestamp`, `checkPermission`, `hasServicesEnabled`, `requestLocationSettings`, `getAccuracyAuthorization` on the modern API. Addendum A3's "compat wrapper drops it" is correct.
- Android manifest already has FINE + COARSE location (`android/app/src/main/AndroidManifest.xml:3-5`); no background location. This matches NFR-11.
- `react-native-maps` ≥ 1.26.1 is compatible with RN 0.87 New Architecture (bare CLI app, no Expo needed).
