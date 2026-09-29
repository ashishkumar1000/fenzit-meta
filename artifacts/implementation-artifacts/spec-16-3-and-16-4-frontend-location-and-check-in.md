# Spec — Stories 16-3 & 16-4: Attendance Location Capture + Today Screen (Frontend)

- **Stories:** 16-3 (attendance-only location capture service) + 16-4 (CheckInOutButton & Today screen) — one batch, one spec, one review, one commit (the paired-story pattern).
- **Repo:** fenzo-app, plus ONE small additive BE change that ships first (see §1 — a genuine gap, not new scope).
- **Status:** Spec revised after adversarial review (§8); implementation next.
- **Sources:** epics-attendance-leave.md §16.3/§16.4; PRD FR-7, FR-8, NFR-2, NFR-5, NFR-8, NFR-11, NFR-12; UX EXPERIENCE.md (CheckInOutButton, copy table, state patterns) + DESIGN.md; spec-16-1-and-16-2 (AD-20/AD-21/AD-4/AD-6/AD-7/D11 wire rules); fenzit-be docs/api-contracts.md "Attendance check-in & check-out"; addendum §C2.

## 1. Fix-placement analysis (per the root-CLAUDE.md rule)

Three 16-4 acceptance criteria need data the FE cannot reach on any shipped route:

| AC | Needs | Has today |
|---|---|---|
| Distance hint (haversine, display-only) | Office pin lat/lng | `me/summary` carries officeName only — no coordinates |
| Pre-flight dialog ("It's a holiday. Check in anyway?") | Today's weekly-off/holiday facts BEFORE any request | Nowhere: the day context exists only inside the check-in/out transaction and the POST response |
| Button reads "Check out" / summary card on load | Today's record (checked in? checked out?) | No read route exists at all; `already_checked_in` 409 is the only signal, and learning state by burning a GPS fix + attempt row is wrong |

| Concern | Layer | Why |
|---|---|---|
| Today's day facts, record state, office pin on a read | **BE** (additive fields on `GET /attendance/me/summary`) | AD-7: today is the server's date — the FE must never derive weekday/holiday client-side (device clock skew, hidden holidays). AD-22: day facts have ONE implementation (day-context). All three facts already exist server-side; the read just stops withholding them. No schema change (DB untouched). |
| Capture service (fresh high-accuracy fix, mocked/provider) | **FE** | Device capability; the wire shape is AD-20's, already shipped. |
| Button state machine, offline gate, countdown, dialogs | **FE** | Presentation states (UX-DR2/DR8); the server still owns every decision (NFR-2). |
| NetInfo offline detection | **FE** (new dependency `@react-native-community/netinfo` **^12.0.1** — first major with New-Architecture support; RN 0.87 / newArchEnabled) | Connectivity is a device fact; the AC adds it "in this story". |
| `Retry-After` capture on 429 | **FE** (`toApiError`) | The filter strips `retryAfterSeconds` from the body into the header; `ApiError` carries no headers today — an additive field. |

**Shipping order:** the BE additive change lands in fenzit-be, is committed/pushed/deployed and probed BEFORE the FE consumes it (cross-repo ordering; the 15-9 "BE pre-patch shipped first" precedent). The FE treats the three fields defensively (absent → legacy mode, §2 D5/D11) so the FE never hard-depends on deploy timing.

## 2. Design decisions (locked before implementation)

**D1 — One additive BE change: `GET /attendance/me/summary` gains `officeLatitude`, `officeLongitude`, `today`, `todayRecord`.** No new route: the tab already loads the summary, and a second route would be a second source for the same facts (the 15-10 finding-8 drift class). Shapes:

```jsonc
{
  // existing: officeId, officeName, startTime, endTime, lateCutOffMinutes, weeklyOffDays
  "officeLatitude": 19.076,        // number | null (null when no office anchored)
  "officeLongitude": 72.8777,
  "today": {                        // active state ONLY — null otherwise
    "date": "2026-09-29",
    "isWeeklyOff": false,
    "isHoliday": false,
    "holidayName": null,
    "isWorkingDay": true
  },
  "todayRecord": {                  // active ONLY; null when no record today
    "checkinAt": "2026-09-29T10:22:00+05:30",
    "checkoutAt": null,
    "lateMinutes": 0,               // null when no rule covers today (D7 of 16-1)
    "isLate": false,
    "workedMinutes": null,          // null until check-out
    "earlyCheckout": null,
    "earlyCheckoutMinutes": null
  }
}
```

Same field names/semantics as the check-in/out responses; tenant-offset instants per 16-1 D11. Implementation reuses the day-context pure helpers (`isoWeekdayOf`, `isWeeklyOffDay`, `minuteOfDayInTz`, `computeLateMinutes`, `computeEarlyCheckoutMinutes`); the instants→minutes truncation currently inline in `recordToResponse` is extracted as `workedMinutesBetween` and imported by both — **one implementation of every piece of the math** (AD-22). New reads: office pin (`attendance_offices` by tenant+office), today's holiday row, today's `attendance_records` row, `tenants.timezone` — all in the existing active branch; `upcoming` answers `today: null, todayRecord: null`; `EMPTY_ME_SUMMARY` (the frozen honest-empty object) gains the four null fields so every state answers one shape. Leave-aware expected-end (17-4 D3 midpoint) is deliberately NOT folded into `todayRecord` yet — Epic 18's grading concern.

**D2 — The capture service is new, separate, and uses the MAIN nitro API (named exports).** `src/services/location/attendanceLocation.ts`: `import { getCurrentPosition } from 'react-native-nitro-geolocation'` — the main entry has NO default `Geolocation` object (only `/compat` does; that is the job flow's import). Options exactly `{ accuracy: { android: 'high', ios: 'best' }, maximumAge: 0, timeout: 15000 }`. The main API is the only one that returns `mocked`/`provider` — precisely why the flows cannot share a function. Success maps to:

```ts
{ latitude, longitude, accuracyM, mocked: boolean | null, provider: string | null, fixAgeMs }
```

`mocked: undefined` → `null` (null = not detected); `provider` passes through or null; `fixAgeMs = clamp(Date.now() − position.timestamp, 0, 86_400_000)` — the DTO's `@Max` cap; **a computed age > 30 000 ms (`FIX_MAX_AGE_MS`) is pre-rejected locally** as `stale` without any network call (a doomed submission would 422 with no attempt row and no feedback). The remaining skew case (device clock wrong by >30 s) surfaces the stale message and re-captures on the next tap; accepted — the PRD's design is that the server judges staleness from the client-sent age. Failures are a CLOSED union the UI branches on: `timeout` (code 3), `permission` (1), `unavailable` (2, and Play-services/settings codes 4–5), `stale` (local pre-reject), `unknown` (incl. −1). Each maps to its own message; `timeout` ≠ `low accuracy` (never obtained vs obtained-and-rejected). **NFR-11: capture happens only inside the check-in/out flow — no watchPosition, no locate-on-mount, nothing stored.** The job helper `features/technicianApp/geolocation.ts` is untouched (AC + NFR-12).

**D3 — Permission states live in `src/services/location/attendanceLocationPermission.ts`, layered permission-first.** One resolver + one remediation function:

- `checkPermission()` first: Android `undetermined` → `PermissionsAndroid.request` (show the OS dialog); `NEVER_ASK_AGAIN` result → Settings. iOS `undetermined` → nitro `requestPermission()` (shows the prompt); `denied`/`restricted` → Settings **directly** (iOS has no in-app re-prompt — a denied user's first tap must not be a dead tap).
- Granularity only after permission: Android `ACCESS_COARSE_LOCATION`-only → `preciseOff` (OS "Approximate"); iOS `getAccuracyAuthorization()` `'reduced'` → `preciseOff`, `'unknown'` (pre-iOS-14) → treat as `granted` and let a failing capture surface the truth (never block a user the OS cannot classify).

Resolver output: `'granted' | 'denied' | 'preciseOff' | 'serviceOff'`. Button labels per state: denied → "Turn on location to check in"; preciseOff → "Turn on precise location to check in" (distinct states per addendum §C2). Remediation: `Linking.openSettings()` for all Settings paths. **Re-probe on every AppState `'active'` while the tab is focused** (cheap, permission-check only, no GPS): a user returning from Settings must never stay stuck on a blocked label (UX floor: never dead-ended).

**D4 — The button state machine is a pure model** (`features/attendance/today/attendanceTodayModel.ts`), derived in one function from `{ permission, online, factsKnown, record, resolving, dialogPending, rateLimitedUntil, now }`:

`offline` → `permissionDenied` → `preciseOff` → `serviceOff` → `rateLimited` → `dialogPending` (latched) → `resolving` → `done` (record with checkoutAt) → `readyOut` → `readyIn`. First match wins. Priority rationale: offline blocks everything; location states block the tap legally; rate-limit's disabled-ness is time-bound; `dialogPending`/`resolving` are the two latches that make double-taps no-ops (§2 D5's flow); done replaces the button entirely ("never both visible at once"). `factsKnown` (D11) gates `readyIn`/`readyOut` — no interactive Check in until the summary's facts have landed.

**D5 — Pre-flight dialog (16-4 scope: weekly off / holiday only), before ANY GPS work, fully latched.** Sequence per tap: press → `dialogPending` latch set synchronously → tap-time `NetInfo.fetch()` offline re-check → if `today.isWeeklyOff || today.isHoliday` → `Alert.alert("It's a holiday. Check in anyway?", undefined, [{ text: 'Cancel', style: 'cancel', onPress: clearLatch }, { text: 'Check in', onPress: proceed }])` — the full three-argument form; the default one-argument Alert has only OK and could never confirm (review CRITICAL). The **Confirm handler re-runs the offline check** (a new moment of decision — the network may have changed during the dialog). Confirm → clearLatch → capture+submit; Cancel/dismiss → clearLatch, **no request at all** (AC). While latched or resolving, further taps are no-ops (one dialog, one request — two fresh keys would burn a real counted attempt). Normal working day → straight to capture. `confirmLeaveCancel` is NOT sent in this story (leave dialogs are 17-8); the defensive `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` renders the neutral holding string "You're on leave today. Checking in will cancel today's leave. Continue?" until 17-8 builds the real dialog (that is the PRD's user-facing copy, not the enum's dev text). If `today` is **absent but the summary loaded** (legacy BE pre-deploy), no dialog fires — the server's dayContext still records the truth (D11 distinguishes this from not-loaded).

**D6 — Offline gate (UX-DR8).** `@react-native-community/netinfo@^12.0.1`. The Today view subscribes to connectivity while focused; offline → blocking message ("You're offline. Check-in needs a working connection.") + button disabled. The tap handler AND the dialog-Confirm handler re-check `NetInfo.fetch()` before any network call. No offline queue (PRD: none).

**D7 — Distance hint honours NFR-11: no background location, no locate-on-mount. ⚠ AC AMENDMENT (flagged for user ratification).** The AC's "When it renders → plus a live muted-text distance hint" cannot be met without capturing location outside check-in/out, and NFR-11 says location is captured "only at the moment of Check-in/Check-out, never tracked in the background". Decision (Epic-16 scope): the hint renders from the most recent capture fix of this screen session — the below-button area shows, in order: the server's rejection copy (`too_far` carries the authoritative distance + radius), else the local haversine hint ("You are N m from {office}") from the last fix, else nothing. Display-only, never gates (NFR-2). If the user wants a pre-attempt hint, that needs an explicit one-shot-locate exception to NFR-11 — a follow-up decision, not built now.

**D8 — Instants are formatted by string slicing, never `new Date()`.** New pure util `src/utils/offsetInstant.ts`: `formatOffsetInstantTime("2026-09-29T10:22:00+05:30") → "10:22 AM"` (12-hour per NFR-5), `formatOffsetInstantDate(...) → "29 Sep 2026"` — parse the wall-clock parts verbatim; the device timezone never touches them (AD-7). `workedMinutes → "8 h 08 m"` helper alongside. Epics 17–19 reuse this util.

**D9 — Idempotency: one fresh UUID v4 per tap** (`generateIdempotencyKey()` at submit time) as `X-Idempotency-Key`. A timeout followed by a new tap sends a NEW key (a new attempt); if the first landed, the server answers `409 ATTENDANCE_ALREADY_CHECKED_IN/OUT` and the hook treats those two codes (only those) as **state recovery**: a forced, gap-bypassing summary refetch (D12) renders the true state. A raced key across employees answers `409 DUPLICATE_RESOURCE` — NOT a recovery path; it renders the server message like any other conflict.

**D10 — Write service `services/resources/attendanceCheckIn.ts`** (plain apiClient functions): `checkIn(capture)` / `checkOut(capture)` → typed 201 responses. The hook converts `ApiError` by `code`, **branching on the exact wire strings** (`ATTENDANCE_TOO_FAR`, `ATTENDANCE_LOW_ACCURACY`, `ATTENDANCE_MOCK_LOCATION`, `ATTENDANCE_STALE_FIX`, `ATTENDANCE_RATE_LIMITED`, `ATTENDANCE_ALREADY_CHECKED_IN/OUT`, `ATTENDANCE_NOT_CHECKED_IN`, `ATTENDANCE_NOT_TRACKED`, `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED`) — never lowercase outcome slugs, which do not exist on the wire. `toApiError` gains `retryAfterSeconds?: number` parsed from the `Retry-After` header (integer seconds only; NaN/absent → undefined). Handling: the four 422 location outcomes → ready + server message verbatim, retry immediate; `ATTENDANCE_RATE_LIMITED` → `rateLimitedUntil = now + awarded×1000` (awarded = header value, else 600); `ATTENDANCE_NOT_CHECKED_IN`/other catalogued codes → the server's `ApiError.message` (it is the PRD copy, e.g. "Check in before checking out"); `ATTENDANCE_NOT_TRACKED` (403, owner disabled mid-session) → force the access-store refresh so the tab catches the flip, plus the server message; transport failures (`NETWORK_ERROR`/`TIMEOUT`) → their own copy. Countdown rules: displayed remaining is clamped to the initially awarded seconds (never extended); re-derived on foreground; backgrounded timer pause is acceptable — expiry renders on return, and a stale tap merely re-429s harmlessly (uncounted).

**D11 — Screen composition + failure posture.** `AttendanceTabScreen` (active only) renders `AttendanceTodayView` ABOVE the existing `AttendanceSummaryView`: office name + 12-hour timings line, the `CheckInOutButton` (56px — the button component owns its own Pressable shell at `touch.large`; `Button`'s max size is 52 and its `style` cannot reach the inner pressable), the outcome/message area, and the done summary card after check-out (times at 36px per DESIGN.md's `checkin.time`, "8 h 08 m", Late flag when known). Mid-checked-in state shows "Checked in 10:22 AM · Late by 22 min" above the Check out button. **Failure posture:** while the summary's first load has not landed (loading or errored), the Today section shows its own loading/error-retry state and NO interactive check-in (facts unknown = the holiday gate cannot fire). `today` absent-but-loaded → legacy mode (D5). `upcoming`/`history_only` render no check-in control (absent, not disabled). **Accessibility:** every settled outcome and state flip announces via `AccessibilityInfo.announceForAccessibility` (house precedent from 15-6); the countdown announces "Try again in N minutes" (words, not M:SS).

**D12 — State freshness: the POST response is the render source; forced refetches bypass the min-gap.** `useAttendanceSummary` gains a forced mode (bypass the 30 s min-gap, deduped via its in-flight ref) used by: (a) post-write consistency refetch, (b) the D9 409-recovery path, (c) foreground returns. Between remounts the hook-local record — `merge(checkInState, checkOutResponse)` (check-out fields win; the check-out 201 carries no late flag, the retained check-in state supplies it) — is the render source; a slow `summary.todayRecord` never overwrites it mid-session. If a POST's `workDate` differs from `today.date` (tenant date rolled over mid-session), adopt the response and force the refetch. Summary refresh also joins AppState `'active'` (a screen open across midnight must not keep yesterday's facts). Unmount during a write (access flips mid-resolve): the hook is unmount-safe; the forced refetch on next entry recovers the state.

## 3. Code layout (files ≤ 300 lines, house structure)

| File | Contents |
|---|---|
| `src/services/location/attendanceLocation.ts` (new) | D2 capture: main-API named `getCurrentPosition`, AD-20 mapping, closed failure union, fixAgeMs clamp + local stale pre-reject. |
| `src/services/location/attendanceLocationPermission.ts` (new) | D3 layered resolver + remediation, per-platform matrix. |
| `src/services/resources/attendanceCheckIn.ts` (new) | D10 check-in/out calls + response types. |
| `src/services/api/apiError.ts` | +`retryAfterSeconds` from the Retry-After header (D10). |
| `src/services/resources/attendanceMe.ts` | Extend `AttendanceSummary` + `normalizeSummary` with the four new fields (defensively absent → null/undefined) — the whitelist normalizer would otherwise strip them. |
| `src/utils/offsetInstant.ts` (new) | D8 string-slice formatters (time/date/worked). |
| `src/features/attendance/today/attendanceTodayModel.ts` (new) | D4 state machine + the copy table (§4) as pure mappings. |
| `src/features/attendance/today/CheckInOutButton.tsx` (new) | Own Pressable shell at 56px per state (spinner, countdown, labels). |
| `src/features/attendance/today/AttendanceTodayView.tsx` (new) | D11 section: office line, button, messages, done card, offline banner, a11y announcements. |
| `src/features/attendance/today/useCheckInOut.ts` (new) | The hook: pre-flight latch, permission probe + AppState re-probe, capture, submit, outcome handling, countdown, forced refetches. |
| `src/features/attendance/me/useAttendanceSummary.ts` | +forced refresh mode (D12). |
| `src/features/attendance/me/AttendanceTabScreen.tsx` | Mounts `AttendanceTodayView` in the active branch. |
| **fenzit-be** `me-summary.model.ts` / `me-attendance.service.ts` / `me-attendance.controller.ts` swagger / `docs/api-contracts.md` summary section / `EMPTY_ME_SUMMARY` (+ specs) | D1: additive fields, one-shape empty, wire docs — the 15-10 drift class closed at all four seams. |

## 4. Copy table (exact strings; AC "exact PRD-specified message")

| Trigger | String | Source |
|---|---|---|
| Holiday/weekly-off pre-flight | "It's a holiday. Check in anyway?" (title; buttons Cancel / Check in) | FE (PRD FR-7 wording) |
| `ATTENDANCE_TOO_FAR` | server message verbatim ("You are N m from {office}. Move within R m.") | BE |
| `ATTENDANCE_LOW_ACCURACY` | server verbatim ("Location not accurate enough, try again in the open") | BE |
| `ATTENDANCE_MOCK_LOCATION` | server verbatim ("Turn off fake location apps to check in/out") | BE |
| `ATTENDANCE_STALE_FIX` / local stale | server verbatim / same copy locally | BE/FE |
| `ATTENDANCE_RATE_LIMITED` | server verbatim + button label "Try again in M:SS" (announced as "Try again in N minutes") | BE + FE |
| `ATTENDANCE_ALREADY_CHECKED_IN/OUT`, `ATTENDANCE_NOT_CHECKED_IN`, `DUPLICATE_RESOURCE`, others | server `ApiError.message` verbatim | BE |
| `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` | "You're on leave today. Checking in will cancel today's leave. Continue?" (holding string until 17-8) | FE (PRD FR-9) |
| GPS timeout | "Couldn't get your location. Move to an open area and try again." | FE (UX table) |
| Permission denied | "Attendance needs your location to check in and out. You can still view your records and apply for leave without it." + button "Turn on location to check in" | FE (UX table) |
| Precise off | button "Turn on precise location to check in" | FE (UX table) |
| Offline | "You're offline. Check-in needs a working connection." | FE |
| Distance hint | "You are {n} m from {office}" via `formatDistance` | FE |

## 5. Test plan (written after implementation works — QA-mindset)

- `attendanceLocation.test` — capture: success mapping (mocked undefined→null, fixAgeMs clamp 0 and 86 400 000, provider passthrough), each failure code → its union member (incl. 4/5→unavailable), local stale pre-reject with NO network call, timeout boundary.
- `attendanceLocationPermission.test` — the layered matrix: permission-before-accuracy ordering; iOS denied/restricted→Settings (no dead in-app re-prompt); undetermined→prompt; NEVER_ASK_AGAIN→Settings; coarse-only→preciseOff; iOS accuracy `unknown`→granted.
- `offsetInstant.test` — +05:30 / −08:00 / Z forms; 12-hour AM/PM; midnight/noon; worked "8 h 08 m" truncation.
- `attendanceTodayModel.test` — full state-priority matrix (offline over permission, rateLimited over ready, dialogPending/resolving as latches, factsKnown gating, done vs readyOut vs readyIn), copy-table mapping per wire code, countdown clamp.
- `useCheckInOut.test` — pre-flight fires only on weekly-off/holiday; dismiss sends nothing; double-tap during dialog/resolving is a no-op; offline re-check at tap AND at confirm; 409 recovery only for the two ALREADY_* codes (DUPLICATE_RESOURCE is not); countdown expiry + foreground re-derive; workDate-rollover adoption; merge(checkIn, checkOut) render source; spinner spans capture+submit.
- `CheckInOutButton.test` / `AttendanceTodayView.test` — one action visible at a time; done card replaces the button; not-interactive while facts unknown; distinct permission labels; a11y announcements on settled outcomes.
(RN gotchas on file: JSX array children defeat exact Text matchers; findAllByProps+asymmetric never matches; Button+inner Pressable double-carry onPress → findAll(onPress) finds 2.)

## 6. Out of scope (explicit)

- Leave dialogs, `confirmLeaveCancel`, and the FR-9 pre-flight — 17-8 (batch 2).
- The leave-aware midpoint in `todayRecord` — Epic 18 grading concern (D1 note).
- Owner dashboard/monthly/day-detail — Epics 18/19.
- Background location, geofence notifications, anything NFR-11 forbids.
- A pre-attempt distance hint — blocked on an explicit NFR-11 exception decision (D7 amendment).
- iOS device validation of the precise-off state (no Xcode machine; Android verified, iOS logic unit-pinned).

## 7. Device walkthrough plan (Pixel 6, vs https://api.fenzit.com)

As Arya (Active @ Hero wala): button states on load (readyIn; post-BE-deploy today facts), check-in inside radius (201 → Check out + checked-in line), double-tap safety, second check-in 409 recovery (button flips to Check out), too_far via distance, check-out → done card with worked hours, permission-denied/precise-off states + Settings round-trip re-probe, offline state (airplane mode), as-found restore (log back in as Ayush). Metro :8081 = current tree; native rebuild required once (NetInfo addition). Suresh (Active @ Yuka, NOT onboarded) — intro flow unchanged, no Today control regression.

## 8. Adversarial spec review triage (2026-09-29) — 2 lenses × step-03

Two independent reviewers (wire-truth lens, UX/state-machine lens) attacked the spec pre-code; 31 raw findings → deduped to 22. Every finding was source-verified before action. Verdict after patches: **SHIP.**

**Patched (21):**
1. CRITICAL — D5's `Alert.alert(title)` one-argument form has only OK: holiday check-in could never be confirmed. Full three-argument form with Cancel/Check in handlers pinned.
2. HIGH — D10 branched on lowercase outcome slugs that never appear on the wire; the wire strings are the `ATTENDANCE_*` catalogue. Fixed + pinned in tests; `DUPLICATE_RESOURCE` explicitly not a recovery path.
3. HIGH — D2 named a nonexistent `Geolocation.getCurrentPosition` default export; the main entry is named exports only. Fixed (D2/§3); options object verified correct.
4. HIGH — `fixAgeMs` unbounded vs the DTO's `@Max(86_400_000)` (a breach 422s with no attempt row and no feedback). Clamped + local stale pre-reject >30 s; residual clock-skew case accepted (server-judges-staleness is the PRD's design).
5. HIGH — D9/D12's recovery refetch was silently swallowed by `useAttendanceSummary`'s 30 s min-gap (stranded on "Check in" after a recovered 409). Forced gap-bypassing refresh mode added to the spec (D12), render source pinned to hook-local merged state.
6. HIGH — Summary first-load failure still rendered a live Check in button (holiday gate could silently vanish → "Worked on holiday" without confirmation). `factsKnown` gating + failure posture added (D11); legacy-BE mode distinguished from not-loaded.
7. HIGH — Midnight rollover/foreground return kept yesterday's facts as truth. AppState-active summary refresh + workDate-mismatch adoption (D12).
8. HIGH — No permission re-probe after returning from Settings ("Turn on location" was a permanent state). AppState-active re-probe added (D3).
9. HIGH — iOS remediation had a dead tap (no in-app re-prompt exists); `restricted`/`undetermined`/`NEVER_ASK_AGAIN` unmapped; resolver order fixed to permission-before-accuracy; iOS accuracy `unknown` branch defined (D3).
10. MEDIUM — The holiday dialog fired while the summary min-gap could leave `today` unknown; tap-order between dialog and NetInfo check unspecified. Latch + sequence + confirm-time re-check pinned (D5).
11. MEDIUM — Checkout 201 carries no late flag; done card could lose it. `merge(checkInState, checkOutResponse)` pinned (D12).
12. MEDIUM — Countdown over-block (missing header → full 600 s; backward clock change; backgrounded timers). Clamp-to-awarded + foreground re-derive + stale-tap-re-429s-harmlessly pinned (D10).
13. MEDIUM — `too_far` copy source unpinned vs the AC's "exact PRD-specified message". Copy table added (§4): server-verbatim for all catalogued codes, FE-built for local states.
14. MEDIUM — 56px CTA does not exist in the Button system (max 52; `style` can't reach the pressable). CheckInOutButton owns its own Pressable shell (D11).
15. MEDIUM — `ATTENDANCE_NOT_TRACKED` mid-session now forces the access-store refresh (tab catches the disable flip); `leave_confirmation_required` renders the PRD copy, not the enum's dev text (D10/D5).
16. MEDIUM — Accessibility announcements were unspecified; house 15-6 precedent applied to all settled outcomes/state flips; countdown announced in words (D11).
17. MEDIUM — FE layout missed `attendanceMe.ts`, whose whitelist normalizer would strip the four new fields silently. Added to §3.
18. MEDIUM — BE layout missed the four wire-truth seams (api-contracts.md, controller swagger, `EMPTY_ME_SUMMARY`, shape doc). Added to §3.
19. LOW — Nitro failure codes 4/5 (Play services/settings) folded into `unavailable` deliberately; −1 → `unknown` (D2).
20. LOW — `workedMinutesBetween` extracted as a shared pure helper instead of a phantom "reuse" claim (D1).
21. MEDIUM — NetInfo unpinned; `^12.0.1` pinned (first New-Arch major) (§1).

**Amended for user ratification (1):** the 16.4 AC's "live distance hint at render" vs NFR-11's "captured only at the moment of Check-in/Check-out" — resolved in favour of NFR-11 (attempt-driven hint, D7 ⚠); a pre-attempt hint needs an explicit one-shot-locate exception and is out of scope.

**Dismissed (0).**

## 9. Change log (implementation record, 2026-09-29)

**BE (fenzit-be, ships first):** `me-summary-today.model.ts` (new pure module — cycle-free layer above day-context: `pickTodayFacts`, `openRecordView`, `closedRecordView`); `me-summary.model.ts` +4 response fields, `EMPTY_ME_SUMMARY` one-shape; `me-attendance.service.ts` +4 reads (office pin, holiday, today's record, tenant tz) in the active branch, `today`/`todayRecord` active-only; `day-context.ts` gains the extracted `workedMinutesBetween` (one implementation with check-in/out responses); controller swagger + api-contracts.md "Today extension" section. Journey-found fix: the probe's record close-out must pair `checkout_attempt_id` (the checkout-pair CHECK). Verified: unit 82 suites/1298 (+16 new today-model tests +4 failure-matrix rows), real-DB 21 suites/428 (+3 journey probes: holiday flip, open-record late grade, closed-record worked minutes), 18-step live HTTP probe green, tsc clean. No migration.

**FE (fenzo-app):** location capture (main-API named `getCurrentPosition`, AD-20 mapping, closed failure union, fixAgeMs clamp + local stale pre-reject); permission module (permission-before-accuracy, preciseOff/serviceOff distinct, prompt-then-Settings remediation, foreground re-probe); `attendanceCheckIn.ts` service; `apiError.retryAfterSeconds` (Retry-After header, integer-only); `offsetInstant.ts` (string-slice formatters); the today/ feature (model state machine + copy table, 56px own-shell CTA, view with done card + offline block, hook with latched dialog/tap-time offline re-checks/countdown/merge); `useAttendanceSummary` forced mode; access-store forced refresh; AttendanceTabScreen mounts the Today view (active only). Device walkthrough on the Pixel 6 against the local BE (new code, production DB) — all ACs exercised: too_far exact copy, 5-count → 429 + ticking countdown, weekly-off dialog cancel/confirm, check-in success + late grade, kill/relaunch → Check out from `todayRecord`, check-out → done card (times/worked/flags, button gone), precise-off label + Settings remediation deep-link, offline block. Walkthrough-found defect fixed: the offline block message renders from STATE (a disabled tap can never set it). As-found restored (DB cleaned via Supabase MCP, Ayush logged back in, config back on production).

**Tests:** FE 180 suites/2007 (+92 across 6 new suites); one test caught a real production bug pre-commit (a stale summary refetch clobbering the fresher local record — `seedRecord` fixed, not the test). tsc clean.

## 10. BMAD code review triage (2026-09-29) — 3 lenses × step-03

Three independent reviewers (blind bug-hunter, wire-contract/edge-case, acceptance auditor) reviewed the full working tree. Raw: 23 findings → **deduped to 12 unique → 10 patched, 2 resolved-by-design, 0 dismissed**; every finding source-verified before action (e.g. the check-out rate-limit claim was traced to the BE's kind-agnostic block read; the Android Alert back-button latch-leak attack was REJECTED — RN's Alert is non-cancelable by default). Verdicts: 2× NEEDS-REWORK (small localized patches), 1× SHIP → all patches applied, re-verified green.

**Patched (10):**
1. HIGH — D12's AppState-active summary refresh was never implemented (only specified): a screen held across midnight kept yesterday's day facts (the pre-flight gate misfires). `useAttendanceSummary` gained the min-gapped AppState listener.
2. MEDIUM — `seedRecord` was date-blind: a backgrounded app crossing midnight kept yesterday's record ("Check out" for a day with no record → dead tap). Date-gated the local-wins branch against `today.date`.
3. MEDIUM — `refreshNow` (forced) joined a possibly pre-write in-flight GET with no follow-up — the 409-recovery race. Adopted the access store's never-join rule (`queuedForced`).
4. MEDIUM — Legacy-BE done-state dead end: the done card was gated on `todayRecord !== undefined`, so a mid-session check-out against the old BE left a permanently disabled button. Card now renders from the hook-local record.
5. MEDIUM — D7's local haversine hint was unimplemented (the AC's second tier). The hook retains the last capture fix; the view renders "You are N m from {office}" (via `distanceUtils`) when no server message shows.
6. MEDIUM — Countdown a11y: `formatCountdownWords` was dead code and the label exposed bare M:SS. Wired: the rate-limited a11y label reads "Check out, try again in N minutes".
7. LOW — Rate-limited label hardcoded "Check in" while checked in (the BE blocks check-out too). The rateLimited state now carries the pending action.
8. LOW — `NetInfo.fetch()` rejections produced a silent no-op tap. `isOfflineNow` fails open (the POST then fails as NETWORK_ERROR with copy).
9. LOW — Non-ApiError write failures rendered nothing. Empty-message fallback to the shared line.
10. MEDIUM — DS-token leftovers (`borderRadius: 14`, `paddingHorizontal: 16`, off-grid `gap: 2`) → `radius.lg`/`spacing.s4`/`spacing.s1`; success transitions now announce ("Checked in"/"Checked out"); two model-test pins updated for the action field; session scaffolding (`arya-facts.ts`) dropped; the config comment debris restored byte-for-byte.

**Resolved-by-design (2):**
- workDate-response adoption (a reviewer MEDIUM): instead of threading `workDate` through the record type (a wire-shape divergence from `todayRecord`), the midnight class is closed by patches 1+2 plus the server's own `ATTENDANCE_NOT_CHECKED_IN` copy; documented here as the deliberate shape.
- Staged-index drift + the `__netinfo-probe` residue: commit-hygiene (resolved at commit time by re-staging; noted so it isn't lost).

**Dismissed (0).**

**Final:** FE 180 suites/2007 tests + tsc clean (post-patch); BE unit 82/1298 + real-DB 21/428 (unchanged by the FE patches); device walkthrough states re-covered by the new/updated tests.
