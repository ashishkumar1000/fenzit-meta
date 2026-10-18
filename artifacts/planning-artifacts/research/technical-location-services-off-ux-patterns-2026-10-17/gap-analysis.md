# Gap analysis: device location-services-OFF handling in Fenzit

**Date:** 2026-10-17 · **Scope:** fenzit-app (frontend), all device-GPS touchpoints · **Inputs:** codebase audit (this repo, `workspace/core/frontend/fenzit-app`) + research run [technical-location-services-off-ux-patterns-2026-10-17](./research.md)

---

## 1. The reported symptom

With the phone's **OS-level Location Services switch OFF**, tapping **"Use my current location"** in the map pin picker shows:

> **"Could not get your location. Try again."** — `src/features/attendance/offices/useLocateMe.ts:40` (`LOCATE_FAILED_MESSAGE`)

No mention that the device toggle is off, and no recovery path. The symptom is reproducible on **Android**; on iOS the same condition happens to produce a different, accidentally-better message (see §4).

## 2. Complete location touchpoint inventory (audit)

The app uses device GPS in **9 places** via `react-native-nitro-geolocation` ^1.4.3 (error codes: `-1` internal, `1` permission, `2` unavailable, `3` timeout, `4` Play Services missing, `5` settings not satisfied — documented at `src/features/technicianApp/geolocation.ts:96-98`). Maps + address search use Google Places via our own backend (no device GPS at runtime).

| # | Touchpoint | Files | "Use my location" trigger | What the user gets today when device services are OFF |
|---|---|---|---|---|
| 1 | Attendance check-in / check-out punch | `src/services/location/attendanceLocation.ts`, `src/features/attendance/today/useCheckInOut.ts:240` | The punch button | **Android: correct** — pre-tap probe sets `serviceOff` state; copy "Location services are unavailable. Turn on location and try again." (`attendanceTodayModel.ts:450`), button label "Turn on location to check in". **iOS: wrong** — probe has no iOS services check (`attendanceLocationPermission.ts:59-72` reads only permission+accuracy); services-off surfaces as kCLErrorDenied → code 1 → labeled *permission-denied* with copy "Attendance needs your location to check in and out…" and remediation into the app's own settings page, which cannot reach the master switch |
| 2 | Geofence prescreen (30s one-shot + live stream) | `usePunchPrescreen.ts:62,99,114-118` | No (background probe) | Silent by design ("punch fails open") — acceptable |
| 3 | Attendance location probe | `attendanceLocationPermission.ts` | No (probe) | The model to copy — but Android-only for services-off |
| 4 | **Office pin placement (owner, attendance setup)** | `useLocateMe.ts` + `MapPinPickerScreen.tsx:218-230` + button `PickerMapArea.tsx:106-114` | **YES — "Use my current location"** (`PickerMapArea.tsx:111`) | **The reported gap.** Generic failed message, no services-off wording, no settings path |
| 5 | **Customer location pin (owner, Add Customer)** | same picker, `mode='customer'`, from `AddCustomerScreen.tsx:454-467` | **YES — same button** | Same gap |
| 6 | Silent Android map centering | `MapPinPickerScreen.tsx:150-172` | No (silent) | Silent — acceptable |
| 7 | **Job workflow "verify location" step (technician)** | `LocationCaptureScreen.tsx:44-82` | Auto-capture on screen open | **Worst gap: fully silent.** Capture failure AND permission denial are swallowed; the workflow advance posts with `latitude/longitude/accuracy = null` (`:52-59, :63-76`). The technician gets zero feedback that location wasn't recorded |
| 8 | Signature step fix | `useSignatureSave.ts:102-111` | No (silent) | Silent by design, server records omission — defensible, but invisible |
| 9 | Attendance intro permission ask | `AttendanceIntroScreen.tsx:64-72` | Permission only | Ignores the helper's error strings; generic message only on throw |

**Not GPS:** address autosuggest / reverse geocoding (`src/services/resources/places.ts`) — server-side, unaffected by the device toggle. This is important: **a manual-fallback path already exists inside the same map picker** (the address search sheet).

## 3. Root cause of the symptom (mechanism)

```
device services OFF (Android)
  → nitro returns code 2 / 4 / 5
  → geolocation.ts:122-136 rethrows as MESSAGES ('Location services unavailable')
  → useLocateMe.ts:77-80 classifies by STRING MATCH — only 'timed out' is recognized
  → lands in 'failed'
  → "Could not get your location. Try again." — dead end, no settings link
```

Three compounding defects:

1. **Error vocabulary is stringly-typed in the job-flow stack.** `geolocation.ts` destroys the numeric codes (2/4/5 = services-off family) by rethrowing messages; the only consumer that needs them (`useLocateMe`) re-classifies by substring. The attendance stack got this right with a closed typed union (`attendanceLocation.ts:33-41`) — there are **two parallel location stacks with two error vocabularies**, duplicated capture strategy (`attendanceLocation.ts:88-114` ≈ `geolocation.ts:163-191`).
2. **No pre-tap services check on the picker screens.** The attendance screen probes on focus and renders the blocked state *before* the tap; the map picker never checks.
3. **Every settings deep-link in the app is `Linking.openSettings()` — the app's own settings page.** Nothing opens Android's location-source panel (`ACTION_LOCATION_SOURCE_SETTINGS`), and the "Open settings" ghost button in the picker (`PickerBottomCard.tsx:49-53`) is gated on *two permission denials*, a path services-off never takes.

**iOS specifics:** services-off arrives as `kCLErrorDenied` → code 1, which the app maps to *permission* everywhere. On iOS, `CLAuthorizationStatus.denied` deliberately conflates app-denial, master-switch-off, and airplane mode; `CLLocationManager.locationServicesEnabled()` is the documented discriminator (research.md [2]) — the attendance probe simply never calls an equivalent of it on the iOS branch.

## 4. What platforms, libraries, and other apps do (from [research.md](./research.md))

- **Platform contract:** iOS conflates the states — the app must discriminate with `locationServicesEnabled()` and can re-detect on return via `didChangeAuthorization` [2]. Android exposes `isLocationEnabled()` [4] **and ships the recovery UI**: `checkLocationSettings()` → native one-tap "turn on location" dialog [5].
- **Our own library already supports the pattern.** react-native-nitro-geolocation (actively maintained; 2.0.2 on 2026-09-13) documents `hasServicesEnabled()`, `getProviderStatus()` (the API the attendance probe already calls on Android), `watchProviderStatus()` (iOS authorization changes / Android provider broadcasts), and — in v2 — `requestLocationSettingsDetailed()` which shows **Android's native resolution dialog** [35][36]. The fix needs no new dependency.
- **UX bar:** show the state close to the trigger, name the actual cause, offer one remedy, don't dead-end — link to "the exact place in the device's settings where they can reverse their decision" [25][26]. Uber's services-off banner is the canonical copy: **"Location services are turned off. Please enable them to continue."** [38]. Apple's own guidance: verify services *before* use; proactive feature-disabling beats reacting to errors [29]. Google Maps degrades to last-known instead of dead-ending [41].
- **Ecosystem trap to avoid:** `react-native-permissions` has **no** services-toggle check (the commonly cited `checkLocationServices()` does not exist in v5.x — overturned against primary source) [14]. The services APIs live in the geolocation library we already ship.

## 5. Gap statement

> Fenzit treats "device location services off" as an anonymous transient failure. Four of the nine touchpoints surface *something*; only one (attendance/Android) names the cause; two owner-facing flows show a generic dead end; one technician flow silently records nulls. The platform provides cheap detection and (on Android) a native one-tap recovery that the app never invokes.

**Impact:** owners hit it during setup (office + customer creation — both blocked dead-end), technicians hit it in the field with a silent data-quality consequence (steps advanced without coordinates), employees on iOS get a wrong diagnosis ("needs your location…" permission framing) for a device-level cause. This is a support-cost and setup-completion risk, and in the verify-location case a silent data integrity gap.

## 6. Recommendations (all frontend — `fenzit-app`; no BE/DB change required)

| # | Priority | Recommendation | Why this layer |
|---|---|---|---|
| R1 | **P0** | **Map picker (office + customer): typed failure classification + services-off state.** Stop classifying by substring; consume the numeric/string codes (2/4/5 → `servicesOff`). Pre-tap check via `hasServicesEnabled()`/`getProviderStatus()` on focus. Copy: *"Location services are turned off on your device. Turn them on to place the pin."* Primary action (Android): native enable-location dialog or guarded `ACTION_LOCATION_SOURCE_SETTINGS` intent (guard `ActivityNotFoundException` — Samsung crash reports) [42][43]; (iOS): `openSettings` + re-check on return. Secondary action: point at the address-search sheet that already exists in the same screen — the manual fallback costs nothing | Symptom is in FE error mapping; detection + recovery are device-side |
| R2 | **P0** | **Attendance: fix the iOS services-off misclassification.** Extend the probe's iOS branch with a services check (nitro `getProviderStatus()` / `hasServicesEnabled()`) so services-off maps to the existing `serviceOff` state instead of `denied`; iOS remediation copy should say the *device* switch is off; re-check on foreground (already happens) | Same state machine already exists; only the iOS branch mislabels |
| R3 | **P1** | **Verify-location step (technician): decide the contract, then surface it.** Today failures advance with nulls silently. Either (a) block + show the four-state UI before advancing, or (b) keep fail-open but show a persistent "Location not recorded" note on the step. This is a product decision (data integrity vs flow friction) — see Open questions | FE UX; BE already accepts nullable coordinates |
| R4 | **P1** | **Unify the two location stacks.** Extract the attendance-style typed failure union + probe into one shared location utility so all touchpoints inherit the same four-state behavior (ready / permission-denied / services-off / transient-failure). Kills the duplicate capture strategy and the string-matching | Root cause is architectural (two vocabularies); one owner prevents re-planting |
| R5 | **P2** | **Evaluate nitro-geolocation 2.x for `requestLocationSettingsDetailed()`** (native Android resolution dialog, string error codes). Verified actively maintained; note the `/compat` surface keeps numeric 1/2/3 while v2 renames codes — budget a migration, don't rush it into R1 | Optional capability upgrade, not required for the fix |
| R6 | **P2** | **Adopt the copy system:** permission-denied ≠ services-off ≠ timeout, each with one primary remedy; rationale formula "[app] would like to access your location so that you can [verify attendance / place the pin / verify the job step]" for priming moments [26]; never nag — show states on focus, not repeated interrupts [26] | NN/g + Uber exemplars |

**Proposed copy (services-off states), following Uber/NN/g patterns:**
- Picker (Android): "Location services are turned off on your device. Turn them on to place the pin." → [Turn on location] [Search address instead]
- Picker (iOS): "Location is turned off for your device. Enable Location Services in Settings to place the pin." → [Open Settings] [Search address instead]
- Attendance iOS (fixing mislabel): reuse the existing serviceOff copy — "Location services are unavailable. Turn on location and try again."
- Verify-location (if blocking): "We couldn't verify your location because location services are off. Turn them on and try again." → [Turn on location] [Continue without location]

## 7. Open questions (need product/user decisions)

1. **Verify-location step:** should a technician be able to advance when location can't be captured (current behavior), or should services-off/permission-denied block the step? (R3)
2. **Android recovery preference:** native resolution dialog (needs 2.x or a small native call) vs settings intent — dialog is one-tap but dismissable; intent always works. Ship intent first and add dialog with R5?
3. **nitro 2.x upgrade:** now (unblocks the native dialog + string codes) or after the P0 fixes ship on 1.4.3?
4. Device-level verification on real iOS/Android devices with the master toggle off (the research's own open question: iOS's exact system-alert behavior is secondary-sourced only).

## 8. Source map

- Internal evidence: file:line citations in §2–§3 from the codebase audit of `workspace/core/frontend/fenzit-app` (2026-10-17).
- External evidence: all `[n]` references resolve in the [source appendix of research.md](./research.md#source-appendix) (43 sources, 11 verified / 2 unverified claims).
