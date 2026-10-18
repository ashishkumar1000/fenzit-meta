---
title: 'Location-services-off detection, messaging, and recovery across Fenzit touchpoints'
type: 'feature'
ticket: ''
created: '2026-10-17'
status: 'in-progress'
route: 'full'
route_source: 'auto'
review: ''
review_source: ''
lenses_ran: []
review_loop_iteration: 0
baseline_revision: '098aa5555f56338896ed68947c0248de392574f1'
context: ['artifacts/planning-artifacts/research/technical-location-services-off-ux-patterns-2026-10-17/gap-analysis.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** With the phone's Location Services switch OFF, Fenzit shows a generic "Could not get your location. Try again." on the office/customer map picker, silently records null coordinates on the technician verify-location step, and mislabels services-off as permission-denied on iOS attendance — users are never told the device toggle is off or how to fix it.

**Approach:** Add one shared device-location helper module (services check, typed failure classification, platform-split remediation), then apply the four-state model (ready / permission-denied / services-off / transient) to the map picker, the technician verify-location step (BLOCKS on services-off — user decision), and the attendance iOS probe.

## Boundaries & Constraints

**Always:**
- Probe services + permission BEFORE any capture on the picker and verify screens; name the actual cause in copy (never a bare "couldn't get location" for a device-toggle state).
- Stay on nitro-geolocation 1.4.3 — `hasServicesEnabled()`, `getProviderStatus()`, `requestLocationSettings()` already exist there.
- Android remediation ladder: native enable-location dialog (`requestLocationSettings`) → guarded `Linking.sendIntent('android.settings.LOCATION_SOURCE_SETTINGS')` → `Linking.openSettings()`; iOS: `Linking.openSettings()` + re-probe on screen focus/return.
- Android dialog success auto-retries the locate/capture (one-tap recovery).
- Copy per gap-analysis.md §6 (services-off wording, "Search address" fallback on picker).
- Verify-step contract (user decisions 1a/2a, 2026-10-17): BLOCK on permission-denied as well as services-off (never advance with nulls for user-fixable device states); GPS timeout = retry, then an explicit labeled [Continue without location] after 2 failed attempts.

**Never:**
- No backend/DB changes; no nitro package upgrade; no new location/permission library.
- ~~No automated tests in this session~~ (AMENDED 2026-10-17 late evening — human renegotiated: user attached a device and ordered rigorous corner-case testing of the feature BEFORE commit, with zero regressions to currently-working flows. Tests are written against the I/O matrix after implementation; commit only after the full suite passes and BMAD review is clean. No push without explicit consent.)
- Do not merge the attendance location stack into the job stack — attendance gets only the iOS probe fix.
- No permission re-prompt loops; no repeated dialogs (probe on focus, not on timers).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Picker locate, healthy | services on, permission granted, tap "Use my current location" | pin placed as today | n/a |
| Picker locate, services OFF | tap | inline services-off notice: "Location services are turned off on your device. Turn them on to place the pin." + [Turn on location] + "Search address" fallback hint; NO generic "Could not get your location" | — |
| Picker [Turn on location], Android | services off | native enable-location dialog; enable → auto re-locate; dismiss → notice stays; dialog unavailable/fails → guarded settings intent; that fails → `Linking.openSettings()` | try/catch each rung |
| Picker [Turn on location], iOS | services off | `Linking.openSettings()`; on return to screen re-probe | no-op safe |
| Verify step, services OFF | screen opens | BLOCKED state, advance RPC never fires: "We couldn't verify your location because location services are off on this device." + [Turn on location] + re-probe on focus | step cannot advance |
| Verify step, permission DENIED (incl. never-ask-again) | screen opens / request denied | BLOCKED state (user decision 1a): "Fenzit needs location access to verify this step." + [Allow location] re-request; never-ask-again → openSettings; advance RPC never fires | step cannot advance |
| Verify step, GPS timeout (services on, permission granted) | no fix after attempts | [Try again]; after 2 failed capture attempts explicit [Continue without location] appears and posts the null-coordinate advance, visibly labeled that the step is recorded without location (user decision 2a) | explicit, not silent |
| Capture fails codes 2/4/5 after positive probe | mid-capture | re-probe: services now off → services-off state; still on → transient (timeout/failed messaging) | no misclassification |
| Attendance iOS, master switch off | Today screen probe | probe state = `serviceOff` (existing Android copy/labels apply unchanged) | fail-open: probe error → treat services as enabled |

</frozen-after-approval>

## Code Map

- `node_modules/react-native-nitro-geolocation/src/api/requestLocationSettings.ts:19` -- Promise wrapper; options Android-only (`enableHighAccuracy?` etc.); iOS native is a no-op resolve (`NitroGeolocation.nitro.ts:126-133`)
- `node_modules/react-native-nitro-geolocation/src/NitroGeolocation.nitro.ts:282,293` -- `hasServicesEnabled()` (iOS: `CLLocationManager.locationServicesEnabled`, ios/NitroGeolocation.swift:77-81) and `getProviderStatus()` (`locationServicesEnabled` populated on BOTH platforms, types.ts:96-123)
- `node_modules/react-native-nitro-geolocation/src/utils/errors.ts:11-23` -- codes -1/1/2/3/4/5; services-off surfaces as 2 (position unavailable), 4 (play services), 5 (settings not satisfied) — NO dedicated code, hence probe-first design
- `src/services/location/attendanceLocationPermission.ts:44-65` -- `iosState()` (add services check here); `androidState()` :30-42 is the probe-order model; remediation :101-142
- `src/features/technicianApp/geolocation.ts:122-136` -- rethrows classified errors as MESSAGES only → attach `.code` when rethrowing (backward-compatible)
- `src/features/attendance/offices/useLocateMe.ts` -- kinds `denied|timeout|failed`; :86-99 classifies via `err.message.includes('timed out')` → switch to `.code` + probe; expose enable-services action
- `src/features/attendance/offices/MapPinPickerScreen.tsx:133-142,354-374` -- `locateError` → PickerBottomCard; address sheet via `searchVisible` + `handleResolvedPlace`/`handleManualAddress` (fallback already exists)
- `src/features/attendance/offices/PickerBottomCard.tsx:46-53` -- error row + ghost button (extend for services-off action button)
- `src/features/attendance/offices/PickerMapArea.tsx:104-112` -- locate button (loading state exists)
- `src/components/ui/InlineNotice.tsx:64-68` -- canonical inline notice, tone `warning`
- `src/features/technicianApp/LocationCaptureScreen.tsx:39-84` -- `captureLocation()`: permission→capture→advance; catch posts explicit-null advance (:63-84); :93-100 back nav; :115-127 retry
- `src/features/technicianApp/useWorkflowAdvance.ts:83-91` -- requiresLocation routing (no change)
- `jest.setup.js:88-111` -- nitro mocks exist for future test session (not now)

## Tasks & Acceptance

**Execution:**
- [ ] `src/services/location/deviceLocation.ts` (NEW) -- shared helpers: `isServicesEnabled()` (fail-open true), `classifyCaptureFailure(err)` (code 1→`permission`, 3→`timeout`, 2/4/5→re-probe then `servicesOff`|`transient`), `showEnableLocationDialog()` (Android `requestLocationSettings({enableHighAccuracy:true})` → resolves `status.locationServicesEnabled`; iOS no-op→resolve true), `openDeviceLocationSettings()` (Android sendIntent→openSettings ladder; iOS openSettings) -- single owner of remediation for all touchpoints
- [ ] `src/features/technicianApp/geolocation.ts` -- attach numeric `.code` to rethrown errors -- unblocks typed classification without breaking message consumers
- [ ] `src/features/attendance/offices/useLocateMe.ts` -- probe services before locate; add `servicesOff` kind + message; classify via `.code` + re-probe (kill string-match); expose `enableServices` action + `errorKind` for UI -- the reported gap
- [ ] `src/features/attendance/offices/PickerBottomCard.tsx` -- services-off row: warning `InlineNotice`-style copy + [Turn on location] button + "Search address instead" secondary hint -- recovery UI
- [ ] `src/features/attendance/offices/MapPinPickerScreen.tsx` -- wire `enableServices`; re-probe services on focus/return; keep sheet fallback wiring -- closes the loop
- [ ] `src/features/technicianApp/LocationCaptureScreen.tsx` -- restructure into phased flow: probe first → BLOCKED state for services-off (per user decision: no advance RPC ever in this state) AND for permission-denied (decision 1a), each with its remediation action + focus re-probe; healthy path captures with retry; after 2 transient failures show explicit [Continue without location] (decision 2a) reusing the null-advance path with a visible "recorded without location" note -- the blocking contract
- [ ] `src/services/location/attendanceLocationPermission.ts` -- `iosState()`: `hasServicesEnabled()` first → `'serviceOff'`; keep fail-open catch -- fixes iOS mislabel

**Acceptance Criteria:**
- Given device services OFF, when "Use my current location" is tapped on office or customer picker, then a services-off notice with a working [Turn on location] action shows — never the generic failed message.
- Given Android dialog accepted, when user enables location, then the picker auto-re-locates without a second tap.
- Given services OFF, when the verify-location screen opens, then no advance RPC fires and the blocked UI shows; after enabling in OS settings and returning, the screen re-probes to ready.
- Given permission denied (never ask again) on the verify step, then the blocked UI shows with a settings route; no advance RPC fires.
- Given 2 GPS timeouts on the verify step (services on, permission granted), then [Continue without location] appears and posting records null coordinates with the visible skip note.
- Given services ON and healthy GPS, all three flows behave exactly as today (no regression on picker, verify step, attendance punch).

## Implementation Notes

- 2026-10-18, device verification (Pixel 6, Android 17, debug build + Metro): matrix rows for the picker verified on real hardware — services-off state shows proactively on mount (probe-first), exact copy renders, [Turn on location] raises Google's native enable-location dialog, and accepting it re-locates automatically. Screenshots: `artifacts/implementation-artifacts/location-services-off-verification-2026-10-18/`.
- 2026-10-18, DEVICE-FOUND BUG + PATCH (`deviceLocation.ts showEnableLocationDialog`): nitro 1.4.3's `requestLocationSettings` re-runs its strict options check the instant the user accepts and REJECTS even when the master switch is genuinely on (observed on Android 17; the old code then fell down the settings ladder, losing the one-tap recovery — recovery still worked via the guarded intent + focus re-probe, but auto re-locate never fired). Patch: on dialog rejection, re-probe `isServicesEnabled()` — device state wins; services actually on → resolve true (auto re-locate preserved); still off → ladder as before. Two race tests added (`deviceLocation.test.ts`); 188 location-related tests green; fix re-verified on device (auto re-locate fired on the accept path).

## Plan Change Log

- 2026-10-17 (post-checkpoint, human instruction): user attached a physical phone and ordered rigorous corner-case testing of the feature before commit, ensuring nothing currently working breaks. This amends the frozen "no tests this session" boundary — every I/O matrix row must be covered by an automated test that runs and passes, plus best-effort on-device verification via adb, before a LOCAL commit (no push). Trigger: user message mid-session. Known-bad state avoided: committing untested state-machine changes to three user-facing flows.

## Review Triage Log

- 2026-10-18 thorough review (lenses: edge-case-hunter, verification-gap). Verdicts: 9 findings — 6 patched, 0 false, 0 deferred. All routed `patch` (caused by this change; direct fixes; no intent_gap/bad_plan → no loopback).
  1. `LocationCaptureScreen.tsx:190-205` [high] `[Allow location]` denied/throws leaves `setBusy(true)` stuck — remediation button disabled forever. VERIFIED (no finally in `requestPermissionAndResume`). → patch A.
  2. `LocationCaptureScreen.tsx:207-233` [medium] Overlapping AppState re-probes when 'active' fires twice before re-render → double capture/advance. VERIFIED plausible (phaseRef updates only on render). → patch C (sync re-entrancy guard).
  3. `LocationCaptureScreen.tsx:156-172` [medium] Header-back during 'advancing' → POST succeeds → `goBack()` on unmounted screen pops the screen beneath. VERIFIED (no mounted guard before goBack). → patch B.
  4. `PickerBottomCard.tsx:62-71` [low] `[Turn on location]` renders dead if `onEnableServices` omitted. VERIFIED (prop optional; no current caller omits). → patch D (1-line guard).
  5. `MapPinPickerScreen.tsx:157-166` [low] Mid-capture services re-probe can set servicesOff after a successful locate without clearing → stale block. VERIFIED narrow (probe race). → patch E (clear error on successful fix in `locate()`).
  6. CLAIM [medium] "healthy verify path behaves exactly as today" falsified: `hasLocationPermission` (nitro `checkPermission`) counts COARSE as granted, so a coarse-only user skips the FINE precise-location ask the old flow always made. VERIFIED against nitro semantics. → patch F (Android checks FINE specifically; iOS unchanged).
  7. verification-gap [patch] Picker AppState/mount re-probe has NO test — settings-rung recovery unpinned. → patch G (test, LocationCaptureScreen listener idiom).
  8. verification-gap [patch] Mid-capture back-out guard ("never a surprise advance") untested — removing the guard keeps the suite green. → patch G (pending-fix unmount test).
  9. verification-gap [patch] Entry permission-ask throw never exercised — a throw leaves probing spinner forever (no Cancel in probing phase). → patch G (reject test; pairs with finding 1).

## Design Notes

Classification rule (why probe-first): nitro has no dedicated services-off code — 2/4/5 all mean "couldn't get a fix for device-level reasons". A positive pre-check plus re-probe-on-failure converts that ambiguity into a certain state. Ladder example:

```
[Turn on location] → showEnableLocationDialog()   // Android native dialog; iOS resolves true (no-op)
  → dialog unavailable/dismissed-fail → openDeviceLocationSettings()  // guarded intent → app settings
  → return/focus → re-probe → services on → auto re-locate
```

## Verification

**Commands:**
- `bun run lint` -- expected: no new errors
- `bun run test` -- expected: all existing suites pass AND the new I/O-matrix corner-case suites pass (every matrix row covered by at least one passing test)

**Manual checks (user, on device):**
- Android: toggle Location off → picker shows services-off notice → [Turn on location] opens native dialog → enable → auto re-locate
- iOS: master switch off → picker notice; openSettings round-trip re-probes
- Android+iOS: verify step with services off → blocked, no advance; enable → proceeds
- Attendance Today with services off (iOS) → "Turn on location to check in" label, not permission copy
