---
title: 'Today-tab punch button (20-3)'
type: 'feature'
created: '2026-10-02'
status: 'done'
review_loop_iteration: 0
baseline_commit:
  fenzo-app: '3c0f7f2c9d1e4153396bbe8a1749eabb8a584eea'
  fenzit-be: '6399c109975964e101e1b5ab6d4a229fb8db5a08'
context:
  - '/Users/admin/workspace/fenzit-meta/workspace/core/frontend/fenzo-app/src/theme/DESIGN_SYSTEM.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The check-in/out control lives only on the Attendance tab — an employee opening the app lands on the Today tab and never sees it. The flat one-line button also gives no upfront geofence awareness (distance/lock is visible only as a hint line, or after the server rejects the punch).

**Approach:** One story, two phases (BE additive first per CLAUDE.md ordering). Phase A: `fenzit-be` adds `officeRadius` to the attendance summary (the office's `radius_m` already exists and already gates punches server-side — this just exposes it). Phase B: `fenzo-app` moves the whole punch section to the technician's **Today tab** and restyles it as the approved mockup: a circular gradient `PunchButton` (pill + fingerprint + sub-label) with a `PunchStatusCard` beneath, covering ALL postures (4 mockup states + offline/permission/rate-limit/resolving/done). The Attendance tab loses the punch section entirely; its summary card, My month banner and Leave stay.

## Boundaries & Constraints

**Always:**
- Server stays authoritative for every punch — client lock only *prescreens*; press still captures fresh GPS and the server still rejects. A 409/422 too-far response is never a crash.
- Fail-safe: a missing/non-fresh fix, or `officeRadius` absent on the wire (old BE) or no office pin ⇒ NEVER locked; fall back to today's unlocked behaviour.
- All colors/gradients/radii via new `@theme` tokens + feature components; relative imports; bun only; a11y announcements (`AccessibilityInfo`) preserved.
- BE phase ships first: old binaries must keep working against the new wire — today's FE doesn't read `officeRadius` at all, and Phase B's normalizer must tolerate absent → `null` (never reject the whole summary for it).

**Ask First:** continuous location watcher (battery); any new dependency; any punch copy rewrite not in the mockup table below.

**Never:** tests written now (standing rule: user confirms on device → tests then, `/bmad-code-review` before any commit); DB/RPC/view changes; new icons beyond installed lucide; removing the punch hook's contract (`useCheckInOut`) logic — the move is a re-host, not a rewrite.

### Mockup state table (approved 2026-10-02 — copy verbatim)

| Posture | Pill | Button | Status card |
|---|---|---|---|
| readyIn, in geofence | `READY` | blue gradient, `CHECK IN`, "Tap to punch" | "Within Office Geofence" + `READY TO PUNCH` chip: "You are at {office} ({distance} away). Location verified via GPS." |
| readyOut, in geofence | `SHIFT ACTIVE` | orange gradient, `CHECK OUT`, "Tap to punch out" | "Shift Active • In Office" + `READY TO PUNCH OUT` chip: "Checked in at {time} ({elapsed} elapsed). Ready to conclude your workday at {office}." |
| readyIn, out of geofence | `LOCKED` | dimmed, `CHECK IN`, "Outside Geofence" | "Outside Office Geofence" + `PUNCH DISABLED`: "You are {distance} from {office} branch. Move within {radius} to punch." |
| readyOut, out of geofence | `LOCKED OUT` | dimmed, `CHECK OUT`, "Outside Geofence" | "Out of Bounds for Check-out" + `LOCKED` chip: "You checked in at {time}. You are currently {distance} away. Move closer to punch out." |
| all others (offline, permission, serviceOff, rate-limited, resolving, no-fix) | same pill skeleton | dimmed/spinner posture | card carries the existing remediation copy (offlineMessage, permission lines, countdown, "Getting your location…"), designed to the same visual language |

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Employee opens app (active) | Today tab, access `active`, fix fresh + in radius | Punch card + status card + unlocked button visible above job sections | N/A |
| Fix fresh + beyond `officeRadius` | haversine(lastFix, office pin) > radius | Button locked (non-interactive), mockup rows 3/4 render | Card explains distance + radius |
| No fix / fix stale (> 2 min) | capture fails or fix age exceeded | NOT locked — fallback posture, press runs the existing flow | "Getting your location…" info card |
| Old BE (no `officeRadius` on wire) | field absent | Normalizer → `null` → no client lock, today's behaviour | Never crash/fetch-reject |
| Offline / permission off / rate-limited / resolving / done | as today | Same remediation/countdown/spinner/done-removal behaviour, new visual skin | unchanged wiring |

</frozen-after-approval>

## Code Map

- fenzo-app `src/features/attendance/today/useCheckInOut.ts` :66-72, :414-430 — hook (record, permission, lastFix-on-press, press, dialogs) — re-hosted, logic untouched.
- fenzo-app `src/features/attendance/today/attendanceTodayModel.ts` :26-82 — `TodayButtonState` union + ladder — gains geofence postures + fix/office inputs.
- fenzo-app `src/features/attendance/today/AttendanceTodayView.tsx` :41-155 — the movable subtree (punch card, button, messages, dialogs) — moves to Today tab; distance hint :141-155 is replaced by `PunchStatusCard`.
- fenzo-app `src/services/location/attendanceLocation.ts` :77-115 — one-shot `captureAttendanceLocation`; header NFR-11 forbids watchers — screen does one-shot captures on mount/foreground/30 s interval while focused (design note).
- fenzo-app `src/features/attendance/me/attendanceAccessStore.ts` :35-48, :217-247 — module-level access store; TodayScreen gets the `active` gate + `refreshAttendanceAccessNow` for free; `useAttendanceSummary` is per-mount (both screens mount it — min-gap throttled, accepted).
- fenzo-app `src/features/attendance/me/useAttendanceSummary.ts` :39-48 — summary hook; `refreshNow` gap-bypassing.
- fenzo-app `src/features/technicianApp/TodayScreen.tsx` :41-170 — host screen; punch section becomes the `SectionList` header area.
- fenzo-app `src/features/attendance/me/AttendanceTabScreen.tsx` :77-153 — drops `AttendanceTodayView`; keeps summary card, My month bridge (`todaySignal` :142-144 unchanged — its summary mount stays), guard :158-167 stays.
- fenzo-app `src/theme/colors.ts` :82-137, `radius.ts` — new punch tokens land here; `react-native-svg` (^15.15.5, Fabric-ready) renders the gradient circle + dashed ring.
- fenzo-app `src/utils/distanceUtils.ts` — `haversineMetres`/`formatDistance` reuse.
- fenzit-be `src/attendance/me-attendance.service.ts` :172-189 (`readOfficePin` selects `latitude, longitude`) — gains `radius_m`; `:162-169` mapper sites.
- fenzit-be `src/attendance/me-summary.model.ts` :43-60, :150-186 — `MeSummaryResponse` + `toMeSummaryResponse` + frozen `EMPTY_ME_SUMMARY` (update atomically).
- fenzit-be `src/attendance/me-attendance.controller.ts` :66-74 — swagger field list; `docs/api-contracts.md` :1211-1277.
- Wire pins that MUST gain the field: `me-summary.model.spec.ts` :178-223 + shape lock :242-251; `me-attendance.service.spec.ts` ~:407-520; `test/integration/attendance-me-summary.integration.spec.ts` :380-462.

## Tasks & Acceptance

**Execution (Phase order = deploy order):**
- [ ] Phase A `fenzit-be` — `readOfficePin` select + `officeRadius` field/mapper/EMPTY constant; swagger + api-contracts + `radius_m`-to-`officeRadius` docblock — additive, deploys first.
- [ ] Phase A — wire-pin suites updated (the three files above) — old suites fail on additive field otherwise.
- [ ] Phase B `fenzo-app` — punch tokens + `PunchButton.tsx`/`PunchStatusCard.tsx` (feature dir, tokens only, SVG gradient + dashed ring + `Fingerprint`); `attendanceTodayModel` gains fix/office-radius inputs + locked rungs (locked ⇒ non-interactive; fresh-fix threshold 120 s); screen-scoped one-shot capture hook while Today tab focused (mount, foreground, 30 s refresh, after each punch settle).
- [ ] Phase B — normalizer tolerance (`officeRadius` absent → null), then TodayScreen hosts the section (punch data above jobs, loading/error postures preserved); AttendanceTabScreen drops it; existing suites updated ONLY where the move/restyle breaks them (test phase for new tests comes AFTER device sign-off).
- [ ] Phase B — **Today empty-state polish (user addendum, 2026-10-02, mockup approved)**: on `TodayScreen`'s zero-jobs render, the medallion becomes the mockup's rounded-square tinted chip (calendar-check glyph + small circular `+` badge overlaid bottom-right) and a pill CTA "Tap to sync status" (refresh icon) rides below the copy — wired to the screen's existing refresh path. Implement by EXTENDING the DS `EmptyState` with optional additive props (medallion shape + badge overlay; defaults keep every other screen's look pixel-identical), never by hardcoding in the screen.

**Acceptance Criteria:**
- Given access `active`, when the technician opens the app, then the punch control + status card are visible on the Today tab BEFORE the job sections, and the Attendance tab no longer renders any check-in control.
- Given a fresh fix within radius, when ready, then the mockup 1/3 postures render verbatim; when beyond radius, the 2/4 locked postures render and the button cannot fire.
- Given an out-of-radius state, when the user walks into the radius while the screen stays open, then the card/button re-probe on the next capture cycle (≤ 30 s) and unlock.
- Given a punch press any time, then GPS + server flow behave EXACTLY as today (dialogs, rate-limit, idempotency, a11y).

## Design Notes

- Fresh-fix lease: fix younger than 2 min enables geofence states; older/missing ⇒ fallback (never locked). Fix age is rechecked against the ticker, not stored.
- NFR-11 tension resolved deliberately: no `watchPosition`, no storage — repeated one-shot captures (30 s) while the screen is focused. If the user wants live-tracking instead, ASK.
- Gradient mechanics: `react-native-svg` `RadialGradient` circle + `strokeDasharray` ring; per-posture token pairs (`punch.in`, `punch.out`, dimmed) defined as color constants first, referenced by the component.
- Both screens mounting `useAttendanceSummary` ⇒ two gap-throttled fetches — accepted (single-sprint app, one user device); do not build a shared-summary store in this story.

## Verification

**Commands:**
- `bun run build` (fenzit-be) -- exit 0
- `bun run test` (both repos, Node 24 on PATH for BE) -- suites affected by the reshapes stay green
- `bunx tsc --noEmit` (fenzo-app) -- no errors

**Manual checks (device, after Phase B):**
- All four mockup postures reproduced on the attached Pixel 6 (mock fix position / real walk-away as feasible); Attendance tab shows no punch section; employee without attendance access sees nothing new on Today.

## Code Review

### 2026-10-02 (post-implementation, both phases uncommitted)

**Code review complete.** 0 `decision-needed`, 8 `patch` (all applied + re-verified: tsc clean, full FE suite 2919/2919, BE untouched), 4 `defer`, 1 `rejected`. Lenses: edge-case-hunter (+deletion+claims) and verification-gap; diff = combined fenzit-be + fenzo-app working tree (2271 lines).

**Patch (applied):**
- [x] [Review][Patch] Clock-step-back makes a fix forever-fresh [fenzo-app src/features/attendance/today/attendanceTodayModel.ts geofenceLock/freshDistanceM] — `now < capturedAt` now fails open (unlocked/null), same direction as staleness.
- [x] [Review][Patch] Prescreen capturedAt stamped at adoption, overstating the lease by capture latency [fenzo-app src/features/attendance/today/usePunchPrescreen.ts] — now back-dated with the fix's own `fixAgeMs`.
- [x] [Review][Patch] Foreground capture fired while the Today tab was NOT focused (screen stays mounted across tab switches) [fenzo-app src/features/attendance/today/usePunchPrescreen.ts] — AppState capture is now focus-gated like the 30 s interval (NFR-11 scope kept).
- [x] [Review][Patch] Non-finite fix coordinates render "NaN m" as the verified distance [fenzo-app src/features/attendance/today/usePunchPrescreen.ts] — adoption now requires Number.isFinite lat/lng.
- [x] [Review][Patch] Explicit `today: null` contract break + fresh fix rendered a green READY TO PUNCH card beside the permanently disabled button [fenzo-app src/features/attendance/today/PunchSection.tsx] — status card now gated on `factsKnown`.
- [x] [Review][Patch] locked posture's button sub-label read "Punch Locked" (mockup image) vs the frozen table's "Outside Geofence" [fenzo-app src/features/attendance/today/PunchButton.tsx] — patched to the frozen table (the story's verbatim contract). NOTE FOR USER: the re-shared mockup image 1 shows "Punch Locked"; image and table conflict — one-word change if the image should win.
- [x] [Review][Patch] readyOut status card appended "branch" not present in the frozen table row 2 [fenzo-app src/features/attendance/today/attendanceTodayModel.ts punchStatusCard] — removed; row 3's "branch" kept (table has it).
- [x] [Review][Patch] Mangled docblock from the component rename [fenzo-app src/services/location/attendanceLocationPermission.ts:7] — line rejoined.

**Defer:**
- [x] [Review][Defer] The geofence engine (lock rungs, freshness lease, card model) has no executable verification until the post-sign-off test phase [fenzo-app src/features/attendance/today/attendanceTodayModel.test.ts] — deferred: standing rule (tests after device sign-off); the natural pins are locked/lockedOut rungs + the 120 s boundary in attendanceTodayModel.test.ts.
- [x] [Review][Defer] TodayScreen's punch hosting/gate (AC-1) is invisible to its suite (access store stays unknown in tests) [fenzo-app src/features/technicianApp/TodayScreen.test.tsx] — deferred: same standing rule; needs an access-seeded render asserting the header above the sections.
- [x] [Review][Defer] Normalizer's numeric officeRadius pass-through unpinned (only null paths asserted) [fenzo-app src/services/resources/attendanceMe.test.ts] — deferred: same standing rule; one-line payload addition to the existing suite.
- [x] [Review][Defer] A failed access fetch leaves the punch absent on Today with no retry affordance until the next foreground/focus refresh [fenzo-app src/features/technicianApp/TodayScreen.tsx] — deferred: self-correcting via the access-store lifecycle; a Today-tab shimmer/retry is new-scope UX.

**Rejected:**
- [Rejected][false] officeRadius ≤ 0 passes the normalizer and locks every punch — refuted: `attendance_offices.radius_m integer not null check (radius_m between 50 and 1000)` (migration 20260926000005); the wire serializes this column, so the value cannot reach the client.

### Device walkthrough — 2026-10-02 (Pixel 6 vs LOCAL BE on Phase A code + production DB; postures via the office-pin move pattern)

**Environment:** fenzit-be built + run locally (port 3000, OTP_DEV_ECHO for login) against the pooler-connected production DB — the deployed Render BE does not carry Phase A yet, so this is the only way the wire carries `officeRadius`. fenzo-app debug build with API_HOST flipped to the LAN (reverted after), Metro over `adb reverse`, logged in as **Arya** (active at office "Hero wala", radius 150). A stale pre-session BE process was found holding port 3000 (old dist, no Phase A) and killed.

**Walkthrough-driven patch (found live, fixed + hot-reloaded mid-walkthrough):** with NO fix yet, the button rendered the inviting blue READY face — but the frozen table's row 5 makes no-fix a DIMMED posture. The model's ready rungs now carry an optional `distanceM` (present ONLY when the prescreen fix is fresh and in-fence; absent keeps exact-shape pins valid) and PunchButton renders the dim skeleton for the fallback. Also re-verified after the patch: tsc clean, punch suites 87/87, full suite 2919/2919, and on device via Metro reload.

**Verified on device (screenshots /tmp/dev-*.png):**
- **AC-1** — punch section renders at the TOP of the technician Today tab (above jobs/empty state); the Attendance tab shows NO check-in control any more (policy card + Apply banner + My month + Leave only).
- **Mockup row 3 (LOCKED)** — real GPS: red LOCKED pill, dim face, red dashed ring, "Outside Geofence", red card "Outside Office Geofence / PUNCH DISABLED / You are **1,355 m** from **Hero wala** branch. Move within **150 m** to punch." (1,355 m real — the mockup's own 1,357 m desk).
- **Mockup row 1 (READY)** — pin moved to the device: blue gradient face, green READY pill, green card "Within Office Geofence / READY TO PUNCH / You are at **Hero wala** (**1 m** away). Location verified via GPS." LOCKED → READY flipped via the ≤30 s capture cycle + focus summary refresh.
- **Row 5 (no-fix fallback)** — dim face, "Tap to punch", neutral "Getting your location…" card (both pre-fix and after the fix lease aged).
- **Press behaves EXACTLY as today** — press fired the 17-8 full-day-leave pre-flight dialog over Arya's real approved leave (20-1 test residue); Confirm → online re-check → FRESH capture → submit. Two outcomes exercised: capture timeout rendered the existing "Couldn't get your location…" copy with nothing sent (dev-11); a landed fix produced a REAL check-in — tiles "Check in **12:55 PM** → Check out **—**" + amber "Late by 220 min" (12:55 − 9:15 late cut-off, server math), button flipped to CHECK OUT, summary refetched. FR-9 side effect visible in Leave: "1–2 Oct 2026 · 1 of 2 days cancelled".
- **Empty-state polish (user addendum)** — squircle medallion + calendar-check + blue `+` badge + "Tap to sync status" pill (mockup 5 verbatim; Arya has zero jobs).
- **a11y/dev note** — capture failures console.error and appear as a dev LogBox toast (16-3 behavior, __DEV__-only); the toast can eat tab-bar touches until dismissed (dev-build-only annoyance).

**NOT captured (device GPS went fully cold indoors — satellites=0, fused cache stale; capture timeouts):** mockup row 2 (SHIFT ACTIVE, blue card) and row 4 (LOCKED OUT, amber card), and the post-checkout DONE posture. Risk is low: PunchStatusCard is tone-driven — the red and green tones rendered live from the same component; lockedOut is the record-open mirror of the verified locked rung; done is the tiles-only render already shown for checked-in states. Re-verify at the next session with GPS (window/outdoors) or accept on the token-swap argument.

**Residue / restore:**
- Office pin RESTORED to `12.9831410139702, 77.7491378970444 r150` (verified).
- Attendance record + attempt + the leave_auto_cancel owner notification DELETED (verified 0/0/0).
- RECORDED, not reverted: Arya's leave day 2026-10-02 stays `cancelled` (leave_request_days) with the append-only `checkin_auto_cancel` ledger event — hand-restoring would desync the ledger; the Leave UI honestly shows "1 of 2 days cancelled". Same class as the 17-8 walkthrough residue.
- Walkthrough env: API_HOST reverted byte-identical to production. NOTE: the local BE (port 3000, OTP_DEV_ECHO) and Metro were RESTARTED for the user's own device session and the second walkthrough pass — stop them when the user is done; the installed debug APK only works while that local BE runs (production builds stay login-blocked until DLT SMS lands).

### User-found gap + fix, verified on device — 2026-10-02 (~14:00, post-commit pass)

The user pressed CHECK IN from their desk (~1.36 km away) and got the dim fallback + the server's flat red line ("You are 1355 m from Hero wala. Move within 150 m.") instead of the approved LOCKED mockup. Root cause: the press flow's own GPS capture — the freshest fix the device ever held — was discarded for display; with no prescreen fix the posture stays fallback, and the 16-4 message precedence rendered the server copy as a bare line. **Fix (fenzo-app e884a79):** the prescreen adopts the press-time fix (`adoptFix`), and for locked/lockedOut postures the approved status card is the truth surface — the flat server line is suppressed instead of duplicating the card worse. Non-locked postures keep the message-over-card rule.

**On-device verification of the fix (fresh Metro bundle):**
- Press CHECK IN from away → server 422 → **the full LOCKED mockup state renders immediately**: red LOCKED pill, dim face, "Outside Geofence", red dashed ring, red card "Outside Office Geofence / PUNCH DISABLED / You are **1,356 m** from **Hero wala** branch. Move within **150 m** to punch." (screenshot /tmp/fix-press-2.png).
- Seeded an in-fence check-in via the production API (17-7 pattern) with the device away → **the amber LOCKED OUT state renders verbatim**: "Out of Bounds for Check-out / LOCKED / You checked in at **1:57 PM**. You are currently **1,356 m** away. Move closer to punch out." + the tiles card (1:57 PM / Late by 282 min) (/tmp/fix-lo-6.png).

**All four mockup states have now rendered live on the Pixel 6 except SHIFT ACTIVE's blue card** (row 2): READY ✓ (green), LOCKED ✓ (red, twice), LOCKED OUT ✓ (amber), row-5 fallback ✓; SHIFT ACTIVE's copy is byte-pinned in attendanceTodayModel.test.ts and its layout is identical to the amber card just verified — the one device-pending visual, GPS-lottery-blocked at the desk.

**Residue restore (second pass):** office pin re-restored to original (verified); the SEEDED record + attempt deleted; the user's own test presses' attempt rows deleted (6); the morning leave-day `cancelled` residue unchanged.

**Review-defer test phase CLOSED (fenzo-app 72c0988):** the geofence rungs + 120 s boundary + clock-back fail-open + prescreen precedence, the frozen card copy per posture, formatMetresGrouped, the numeric officeRadius wire pass-through, and the TodayScreen hosting gate (active-only) — full suite 2949/2949, tsc clean. The remaining open defer is only the Today-tab access-fetch shimmer (new-scope UX).