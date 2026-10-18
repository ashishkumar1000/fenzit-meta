---
title: 'technical research: Detecting & communicating device location-services-off in mobile apps'
type: 'technical'
topic: 'Detecting & communicating device location-services-off in mobile apps: platform behavior, library support, and UX recovery patterns'
decision: 'How a React Native app should detect OS-level "location services OFF" vs app-permission-denied vs timeout across every location touchpoint, and which recovery flow to adopt'
source: 'native run'
status: complete
preset: 'standard'
validation: 'normal'
created: '2026-10-17'
updated: '2026-10-17'
claims: { verified: 11, unverified: 2 }
---

# technical research: Detecting & communicating device location-services-off in mobile apps

**Decision this research serves:** How a React Native app should detect OS-level "location services OFF" (the device master toggle) vs app-level permission denial vs timeout, and which recovery UX to adopt, on iOS and Android.

## Executive summary

The evidence says: **detect the device state proactively, before the user taps; name the actual cause in the failure copy; and split the recovery action by platform.** Detection is cheap and synchronous on both OSes — Apple's own guidance is to "always verify that location services are available before you attempt to use them" and to disable location-dependent features in advance, "a more reliable approach than using a service and responding to errors" [29]. Android additionally ships a system recovery dialog (Play-services settings resolution) that turns location on with one tap, and a documented settings intent; iOS has no system dialog, so the app must own the recovery UX there.

Three findings drive the answer:

1. **On iOS the OS conflates the states; the app must discriminate.** `CLAuthorizationStatus.denied` covers app-denied, device-services-off, and airplane mode alike; `CLLocationManager.locationServicesEnabled()` is the documented discriminator [2]. A generic "couldn't get your location" is therefore an app-side mapping failure, not a platform limitation — purpose-built error tables (e.g. `SETTINGS_NOT_SATISFIED=5`, `PLAY_SERVICE_NOT_AVAILABLE=4` vs spec-code `POSITION_UNAVAILABLE=2`) exist precisely to separate these [16][36].
2. **Recovery is asymmetric by design.** Android: `SettingsClient.checkLocationSettings()` → `startResolutionForResult` shows a native "turn on location" one-tap dialog [5]; the app-side geolocation library can wrap it (`requestLocationSettingsDetailed()` in nitro-geolocation v2 [36]). iOS: no equivalent — the documented-safe deep link is the app's own settings page, with re-detection on return via authorization-change callbacks [2][36]; deep-linking the system Location Services screen is undocumented territory (open question).
3. **The UX bar is well established:** display the state close to where location is needed, describe it precisely in human language, offer one remedy and a manual fallback [25][26]; Uber's services-off banner copy is the canonical exemplar — "Location services are turned off. Please enable them to continue." [38]. Do not nag [26].

Biggest caveat: the claim that iOS shows *no system alert* when an app requests location with services off rests on secondary sources only — unverified at primary level (see Open questions).

## Dimension 1 — The platform contract (iOS + Android native behavior)

**iOS conflates, then offers a discriminator.** When location services are disabled or denied and an app starts location updates, Core Location reports `kCLErrorDenied` to the delegate's `didFailWithError` callback rather than throwing or failing silently [1][3]. The `.denied` authorization status deliberately covers three causes — per-app denial, the device master toggle, and airplane mode — and Apple's doc explicitly says to call `locationServicesEnabled()` to determine global availability [2]. The proactive check is the class property `CLLocationManager.locationServicesEnabled()` (iOS 4.0+) [1]; the instance `authorizationStatus()` method was deprecated in iOS 14 as part of the authorization-API rework [10]. When the user re-enables services, the app's authorization returns to its prior state and `locationManager(_:didChangeAuthorization:)` fires — the documented hook for recovering without polling [2]. Apple's recovery affordance for *permission* (CoreLocationUI's `CLLocationButton`, iOS 15+) grants one-time authorization but explicitly not the master toggle — it does not solve services-off [9]. Whether iOS itself alerts the user when services are off could only be confirmed from a secondary source (request-authorization calls do nothing system-disabled; developers are told to check `locationServicesEnabled()` and route to Settings) [8] — primary confirmation was not retrieved (medium confidence, flagged unverified).

**Android separates, and ships the recovery dialog.** The proactive master-toggle check is `LocationManager.isLocationEnabled()` (API 28+), with `isProviderEnabled(GPS/NETWORK_PROVIDER)` as the pre-28 pattern; `MODE_CHANGED_ACTION` broadcasts toggle changes so apps can observe without polling [4]. Google's official recovery flow is `SettingsClient.checkLocationSettings()` with a `LocationSettingsRequest`; on `RESOLUTION_REQUIRED` the app calls `startResolutionForResult`, which shows a native dialog enabling location "with a single tap" [5]. The `SETTINGS_CHANGE_UNAVAILABLE` outcome (no dialog possible; `RESOLUTION_REQUIRED` is the dialog-showable state per the status-code reference [6]) has known gotchas — it can appear after a prior dismissal or in airplane mode [7]. Android 10+ splits background permission and can downgrade to approximate location regardless of declared permissions; a Play-policy location-button requirement applies to future target-API levels for session-based features [11]. Exact fused-client failure codes with the toggle off were not primary-confirmed; blog-level evidence says `getLastLocation()` may simply return null (low confidence) [12]. One practical nuisance: calling `locationServicesEnabled()` synchronously can trip Xcode's main-thread checker on iOS 16+ [13].

**Apple's own pattern is proactive degradation.** "Always verify that location services are available before you attempt to use them… Disabling features in advance is a more reliable approach than using a service and responding to errors," and if data is unavailable, "disable features that rely on location data or provide alternatives" [29]; the authorization article's sample maps `.denied/.restricted` to `disableLocationFeatures()` [34].

## Dimension 2 — React Native library reality

**The generic libraries do not separate the states.** `@react-native-community/geolocation` defines only the web-spec codes `PERMISSION_DENIED(1) / POSITION_UNAVAILABLE(2) / TIMEOUT(3)` and has no services-off API — community issues show services-off surfacing as the catch-all code 2 ("No location provider available", fixed only by enabling device location) [20][21][24]. Current `react-native-permissions` (v5.6.3, released Oct 2026 — the only actively released package of the set) exposes **no** master-toggle check at all — the widely repeated `checkLocationServices()` does not exist in its README or source (verified against the repo; that claim is overturned) — and its `openSettings()` opens the app's own settings page, not the system Location Services screen [14][15].

**The purpose-built geolocation libraries do.** `react-native-geolocation-service` documents a six-entry table — including `PLAY_SERVICE_NOT_AVAILABLE=4` and `SETTINGS_NOT_SATISFIED=5` ("Location service is not enabled or location mode is not appropriate"), giving Android services-off a dedicated code — plus `showLocationDialog: true` (default) that triggers the Play-services enable-location dialog, and iOS `requestAuthorization` resolving `'disabled'` when services are off [16]. It is unmaintained (~4 years since last publish) [17], but its error table is the lineage nitro-geolocation follows. `expo-location` offers `hasServicesEnabledAsync()`, `getProviderStatusAsync()` (services + per-provider availability), and Android-only `enableNetworkProviderAsync()`; its JS layer is a passthrough, so the services-off error code lives in the native module (unverified name) [18][19].

**The nitro lineage (actively maintained) wraps the full pattern.** `react-native-nitro-geolocation` — a New-Architecture/Nitro module for RN 0.75+ — published 1.4.3 on 2026-07-17 and 2.0.0–2.0.2 through 2026-09-13 [35]. Its documented surface includes `hasServicesEnabled()` (device-toggle boolean), `getProviderStatus()` (`locationServicesEnabled` + `gpsAvailable`/`networkAvailable`/`passiveAvailable`), `watchProviderStatus()` (iOS: authorization changes/app activation; Android: provider broadcasts), `getLocationReadiness()` with remediation codes like `enableLocationServices` [36]. Version 2 adds `requestLocationSettings()` / `requestLocationSettingsDetailed()` returning `satisfied/cancelled/unavailable/activityMissing`, with the detailed variant showing "Android's native resolution dialog when available" (iOS never shows a dialog) — and renames error codes to string discriminants (`SETTINGS_NOT_SATISFIED`, `PLAY_SERVICE_NOT_AVAILABLE`), keeping the legacy numeric 1/2/3 contract only in the `/compat` API [36][37]. The Android settings intent itself is stable API: `ACTION_LOCATION_SOURCE_SETTINGS = "android.settings.LOCATION_SOURCE_SETTINGS"` ("Show settings to allow configuration of current location sources"), fireable via RN's `Linking.sendIntent` (Android-only) [23][42] — with an OEM caveat: launching it can crash on some Samsung devices, so guard `ActivityNotFoundException` or fall back to the generic settings intent [43]. For apps that can't take a library upgrade, the standalone `react-native-android-location-enabler` (~1 yr since last publish) wraps the same Android popup [22]. Status of deep-linking iOS to the system Location Services page (`App-Prefs:` schemes): not resolvable this run — open question.

## Dimension 3 — How real apps handle it, and what UX practice recommends

**App evidence is help-center-grade, not screenshot-grade** (search-provider rate limits blocked teardown galleries; absence noted). Uber's rider help confirms the banner pattern for the services-off state — in-app copy "Location services are turned off. Please enable them to continue." and "GPS signal not found." — and its recovery copy routes riders to the exact device paths: iOS Settings → Privacy & Security → Location Services → Uber (+ Precise Location); Android Settings → Location → Apps → Uber → Allow all the time (+ Wi-Fi/Bluetooth scanning) [38]. Lyft publishes a graceful-degradation model ("We only access your location if the Lyft app is running…"), in-app privacy toggles, and labels matching the OS ("Share from request to drop off") [39]. Google Maps degrades rather than dead-ends: when it "can't find your current location… Maps shows the last location you visited," with uncertainty rendered as a light-blue circle [41]. No DoorDash/Swiggy/Zomato/Grab article describing the device-off state was retrievable [40]; users do publicly discuss hitting denied-location states in Swiggy/Zomato after restricting location [33]; a recognized UX-StackExchange thread confirms the design problem is recurring [32], and Google's own help resolves permission errors with generic device fixes rather than an in-app flow [31].

**UX practice converges on four rules.** NN/g's error-message guidelines: show the message close to the error's source, "concisely and precisely describe the issue," offer remedies, use human-readable language, never blame the user [25]. NN/g's permission research: priming copy of the form "[app] would like to access your [resource] so that you can [benefit]" measurably lifts grants (12% baseline lift; up to 81% between strongest and weakest reasons tested) [26]; for the denied/turned-off state, "make it easy for them to grant access… a link to the exact place in the device's settings where they can reverse their decision" (Venmo cited as exemplar) [26]; and avoid request fatigue and disguised dialogs [26]. Platform guidance echoes it: Android system labels ("Allowed all the time", "Ask every time", "Never ask again") should anchor app copy [27][28], and Apple directs proactive feature-disabling with alternatives rather than post-hoc errors [29][30].

## Cross-dimension insights

- **The state discrimination lives in the app layer, not the platform layer — on both platforms.** iOS conflates by design (one `.denied` status [2]); spec-based geolocation APIs collapse services-off into `POSITION_UNAVAILABLE` [20]. Meanwhile both OSes expose cheap synchronous discriminators [1][4] and purpose-built error tables exist [16][36]. So a generic "couldn't get your location" is always a mapping failure in the app: detection is available, and the fix is architectural (one typed state machine), not a message tweak.
- **Recovery UX cannot be identical across platforms, and shouldn't try.** Android's native one-tap resolution dialog [5][36] is strictly better than any custom flow — use it first, settings-intent as fallback [42]; iOS has no equivalent, so the app owns the message-and-deep-link flow there [8], ideally re-checking state on return rather than forcing navigation [2][36].
- **The mature pattern is pre-tap state, not post-tap error.** Apple says so verbatim [29]; Uber's banner is a persistent state surface, not a toast [38]; the decision should treat "services off" as a first-class screen state alongside loading/empty/error — which also matches NN/g's "close to the source" rule [25].

## Contrary evidence

- **Overturned claim:** "react-native-permissions has `checkLocationServices()`" — repeated across the ecosystem, contradicted by the primary repo (README + `src/permissions.ts` contain no such symbol) [14]. Anyone building on that claim adds a dead check.
- **Absence findings:** no screenshot-grade teardown of Uber/DoorDash/Swiggy-class services-off screens is publicly retrievable (rate-limited provider; absence is provider-side, not proof of absence); no DoorDash/Swiggy/Zomato/Grab help page describing the device-off state was found [40]; Apple publishes no primary statement of the services-off alert behavior [8][34].
- The red-team pass did **not** run (validation = normal); the spot-checks above were landing-time verifications of load-bearing claims.

## Recommendations

1. **Detect before asking; render services-off as a first-class screen state.** Pre-check the master toggle (and permission) on screen focus and before any capture; branch UI into four states — ready / permission-denied / services-off / transient-failure (timeout|unavailable). Confidence: high — Apple's own guidance [29], platform APIs [1][4], library support [36].
2. **Name the cause in copy; never ship a bare "couldn't get your location."** Services-off copy should say location is turned off on the device and what to do; follow Uber's banner phrasing [38] and NN/g's rules [25][26]. Match OS label vocabulary [27]. Confidence: high.
3. **Platform-split the recovery action.** Android: trigger the native one-tap resolution dialog (library-wrapped `requestLocationSettingsDetailed()` [36] or direct Play-services check [5]); fall back to a guarded `ACTION_LOCATION_SOURCE_SETTINGS` intent [42][43]. iOS: explain + deep-link via `openSettings` (app's own page) and re-check on return via `watchProviderStatus`/authorization callbacks [2][36]; treat system-page deep-links as unverified territory. Confidence: high (Android) / medium (iOS deep-link specifics).
4. **Own one typed error vocabulary in the app.** Map the library's codes (including 4/5-class codes [16][36]) to the four states in a single utility; do not let string-matching on messages classify failures. Confidence: high.
5. **Always offer a manual fallback and don't nag.** Address search/manual entry covers services-off permanently; show the state when relevant (screen focus), not as repeated interrupts [26][29][41]. Confidence: high.

## Open questions

- Does iOS show any system alert when an app requests location with master services off? (Secondary-only [8]; would need a device test or an authoritative Apple statement — Apple's pages are silent.)
- Can iOS apps still deep-link to Settings → Location Services (`App-Prefs:` schemes), and at what App Review risk? (Unresolved — search rate limits; would need current-device testing + App Review guidance reading.)
- What exact error does Play-services `FusedLocationProviderClient` return with the toggle off? (Low-confidence blog evidence only [12]; would need a device experiment.)
- Screenshot-grade in-app off-states for Uber/DoorDash/Swiggy-class apps (would require device capture; help-center copy is the public proxy).

## Source appendix

| # | Source | Publisher | Pub date | Accessed | Confidence |
|---|---|---|---|---|---|
| [1] | [CLLocationManager.locationServicesEnabled()](https://developer.apple.com/documentation/corelocation/cllocationmanager/locationservicesenabled()) | Apple Developer | undated | 2026-10-17 | high |
| [2] | [CLAuthorizationStatus.denied](https://developer.apple.com/documentation/corelocation/clauthorizationstatus/denied) | Apple Developer | undated | 2026-10-17 | high |
| [3] | [locationManager(_:didFailWithError:)](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanager(_:didfailwitherror:)) | Apple Developer | undated | 2026-10-17 | high |
| [4] | [LocationManager reference](https://developer.android.com/reference/android/location/LocationManager) | Android Developers | undated | 2026-10-17 | high |
| [5] | [Change location settings](https://developer.android.com/develop/sensors-and-location/location/change-location-settings) | Android Developers | undated | 2026-10-17 | high |
| [6] | [LocationSettingsStatusCodes](https://developers.google.com/android/reference/com/google/android/gms/location/LocationSettingsStatusCodes) | Google Play services | 2026-06 | 2026-10-17 | medium |
| [7] | [android/location-samples issue #47](https://github.com/android/location-samples/issues/47) | GitHub (secondary) | undated | 2026-10-17 | medium |
| [8] | [Requesting location (Core Location)](https://www.hackingwithswift.com/read/22/2/requesting-location-core-location) | Hacking with Swift (secondary) | undated | 2026-10-17 | medium |
| [9] | [CLLocationButton (CoreLocationUI)](https://developer.apple.com/documentation/corelocationui/cllocationbutton) | Apple Developer | undated | 2026-10-17 | high |
| [10] | [authorizationStatus() deprecation](https://developer.apple.com/tutorials/data/documentation/corelocation/cllocationmanager/authorizationstatus().md) | Apple Developer | undated | 2026-10-17 | high |
| [11] | [Request location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions) | Android Developers | undated | 2026-10-17 | high |
| [12] | [Fused location provider walkthrough](https://blog.devgenius.io/using-fused-location-provider-api-for-getting-location-in-android-f01034296bb) | Dev Genius/Medium (secondary) | undated | 2026-10-17 | low |
| [13] | [Main-thread warning with locationServicesEnabled](https://stackoverflow.com/questions/73805219/main-thread-warning-with-cllocationmanager-locationservicesenabled) | Stack Overflow (secondary) | 2022-09 | 2026-10-17 | medium |
| [14] | [react-native-permissions README + src](https://github.com/zoontek/react-native-permissions) | GitHub (primary repo) | undated | 2026-10-17 | high |
| [15] | [react-native-permissions releases](https://github.com/zoontek/react-native-permissions/releases) | GitHub | 2026-10 | 2026-10-17 | high |
| [16] | [react-native-geolocation-service README](https://github.com/Agontuk/react-native-geolocation-service) | GitHub (primary repo) | undated | 2026-10-17 | high |
| [17] | [npm: react-native-geolocation-service](https://www.npmjs.com/package/react-native-geolocation-service) | npm | ~2022 | 2026-10-17 | high |
| [18] | [expo-location docs (SDK 58)](https://docs.expo.dev/versions/latest/sdk/location/) | Expo docs | undated | 2026-10-17 | high |
| [19] | [expo/expo Location.ts](https://raw.githubusercontent.com/expo/expo/main/packages/expo-location/src/Location.ts) | GitHub (primary repo) | undated | 2026-10-17 | high |
| [20] | [@rn-community/geolocation README](https://github.com/michalchudziak/react-native-geolocation) | GitHub (primary repo) | undated | 2026-10-17 | high |
| [21] | [npm: @react-native-community/geolocation](https://www.npmjs.com/package/@react-native-community/geolocation) | npm / GitHub releases | ~2024 | 2026-10-17 | medium |
| [22] | [npm: react-native-android-location-enabler](https://www.npmjs.com/package/react-native-android-location-enabler) | npm | ~2025 | 2026-10-17 | medium |
| [23] | [React Native Linking docs](https://reactnative.dev/docs/linking) | React Native docs | undated | 2026-10-17 | high |
| [24] | [geolocation issue #120 + r/reactnative](https://github.com/michalchudziak/react-native-geolocation/issues/120) | GitHub/Reddit (secondary) | undated | 2026-10-17 | medium |
| [25] | [Error-message guidelines](https://www.nngroup.com/articles/error-message-guidelines) | Nielsen Norman Group | 2023-05 | 2026-10-17 | high |
| [26] | [Permission requests](https://www.nngroup.com/articles/permission-requests) | Nielsen Norman Group | 2019-04 | 2026-10-17 | high |
| [27] | [Android location help](https://support.google.com/android/answer/6179507) | Google (Android Help) | undated | 2026-10-17 | high |
| [28] | [Android permissions (Material)](https://m2.material.io/design/platform-guidance/android-permissions.html) | Google Material Design | undated | 2026-10-17 | medium |
| [29] | [Configuring your app to use location services](https://developer.apple.com/documentation/corelocation/configuring-your-app-to-use-location-services) | Apple Developer | undated | 2026-10-17 | high |
| [30] | [HIG: Location button](https://developer.apple.com/design/human-interface-guidelines/location-button) | Apple (HIG) | undated | 2026-10-17 | low |
| [31] | [Maps community: permission denied](https://support.google.com/maps/thread/255132557/share-your-real-time-location-with-others-app-permission-denied) | Google Maps Community | undated | 2026-10-17 | low |
| [32] | [UX StackExchange: what to display if services not enabled](https://ux.stackexchange.com/questions/130251/what-to-display-if-user-does-not-enable-location-services) | UX Stack Exchange | 2019-11 | 2026-10-17 | low |
| [33] | [r/IndiaTech: Swiggy/Zomato location](https://www.reddit.com/r/IndiaTech/comments/1bx2zq5/i_understand_if_they_want_to_use_it_but_why_share) | Reddit (secondary) | ~2024-04 | 2026-10-17 | low |
| [34] | [Requesting authorization to use location services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services) | Apple Developer | undated | 2026-10-17 | high |
| [35] | [npm registry: react-native-nitro-geolocation](https://registry.npmjs.org/react-native-nitro-geolocation) | npm registry | 2026-09-13 | 2026-10-17 | high |
| [36] | [nitro-geolocation API reference](https://react-native-nitro-geolocation.pages.dev/guide/api.html) | nitro-geolocation official docs | undated | 2026-10-17 | high |
| [37] | [nitro-geolocation README](https://github.com/jingjing2222/react-native-nitro-geolocation) | GitHub (primary repo) | undated | 2026-10-17 | high |
| [38] | [Uber: "Unable to Determine My Location"](https://help.uber.com/en/riders/article/why-is-the-app-unable-to-determine-my-location?nodeId=c7f16f6e-e42a-424d-a51d-30ef4e29656c) | Uber Help | undated (live) | 2026-10-17 | high |
| [39] | [Lyft app permissions for riders](https://help.lyft.com/hc/en-us/articles/115012928087-Lyft-app-permissions-for-riders) | Lyft Help Center | undated (live) | 2026-10-17 | high |
| [40] | [DoorDash SafeDash Location Sharing](https://help.doordash.com/en-us/dashers/article/safedash-location-sharing) | DoorDash Dasher Support | undated (live) | 2026-10-17 | high |
| [41] | [Google Maps: location accuracy](https://support.google.com/maps/answer/2839911) | Google Support | undated (live) | 2026-10-17 | high |
| [42] | [Settings reference + AOSP Settings.java](https://developer.android.com/reference/android/provider/Settings) | Android Developers / AOSP | undated | 2026-10-17 | high |
| [43] | [Samsung intent crash + guarded launch](https://stackoverflow.com/questions/33451192/android-settings-action-location-source-settings-resulting-in-crash) | Stack Overflow / MS Learn (secondary) | undated | 2026-10-17 | medium |

## Staleness map

Computed by `recon_kit.py staleness` (windows: version/maintenance ≤ 6 mo · api-behavior ≤ 24 mo · guidance ≤ 60 mo; undated pages take the access month). Tool output:

| Claim | Class | Pub date | Re-check by | Tool flag |
|---|---|---|---|---|
| react-native-permissions v5.6.3 current; no services API | version/maintenance | 2026-10 | 2027-04-01 | fresh |
| nitro-geolocation 2.0.2 current; v1.4.3 line 2026-07 | version/maintenance | 2026-09 | 2027-03-01 | fresh |
| react-native-geolocation-service ~4 yrs stale | maintenance | ~2022 | 2022-07-01 | past due |
| @react-native-community/geolocation ~2 yrs stale | maintenance | ~2024 | 2024-07-01 | past due |
| geolocation-service/nitro error-table semantics (codes 4/5) | api-behavior | 2026-10 | 2028-01-01 | fresh |
| iOS `.denied` conflation + `locationServicesEnabled()` discriminator | api-behavior | 2026-10 | 2028-01-01 | fresh |
| Android `isLocationEnabled`/resolution-dialog/intent contract | api-behavior | 2026-10 | 2028-01-01 | fresh |
| `ACTION_LOCATION_SOURCE_SETTINGS` value + OEM caveat | api-behavior | 2026-10 | 2028-01-01 | fresh |
| Apple "verify before use / disable features" guidance | guidance | 2026-10 | 2031-01-01 | fresh |
| NN/g error + permission guidance (incl. 12%/81% figures) | guidance | 2019-04 | 2024-01-01 | past due |
| Uber/Lyft/Maps help-copy patterns | guidance | 2026-10 | 2031-01-01 | fresh |

Interpretation: the two "past due" maintenance rows flag claims *about* packages that stopped publishing — the underlying facts are stable, but a Refresh should re-pull npm to confirm no revival. The NN/g guidance formally aged past its window in 2024: treat its specific figures (12%/81%) as dated-but-directional, the qualitative rules as standing. Earliest actionable re-check for live decisions: **2027-03** (nitro version claims — re-pull the npm registry and docs site then).
