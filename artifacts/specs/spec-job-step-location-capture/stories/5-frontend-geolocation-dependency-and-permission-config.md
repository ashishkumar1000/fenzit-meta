# Story 5: Frontend — geolocation dependency + native permission config

## Source

- SPEC.md Constraints: "Must use `react-native-geolocation-service` — `fenzo-app` is a bare React Native CLI app (no Expo runtime, no `expo-location` available)."
- frontend-architecture.md section 1 (confirmed: bare RN CLI, zero `expo` deps) and section 2.1.
- stories.yaml id "5".

## Acceptance Criteria

1. `react-native-geolocation-service` is added as a dependency via `bun add react-native-geolocation-service` (no npm/yarn/pnpm lockfiles introduced).
2. Android manifest (`android/app/src/main/AndroidManifest.xml`) declares `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />`.
3. iOS `Info.plist` (`ios/<AppName>/Info.plist`) adds `NSLocationWhenInUseUsageDescription` with real, user-facing copy explaining why the app needs location (e.g. "Used to verify your location when completing job steps").
4. App builds and launches on both platforms with no new native-linking errors (autolinking should pick up the RN module; no manual pod/gradle wiring expected beyond the manifest/plist entries and a pod install on iOS).

## Implementation Notes

- Do **not** use `expo-location` — there is no Expo runtime in this app (zero `expo` package in `package.json` dependencies, verified by repo-wide grep). `react-native-geolocation-service` is the only correct choice per SPEC.md Constraints.
- Files touched: `android/app/src/main/AndroidManifest.xml` (permission entry), `ios/<AppName>/Info.plist` (usage-description key), `package.json` + `bun.lock` (new dependency), and an iOS `pod install` run (not a tracked file, but required after adding a native dependency).
- This is the only story in epic-7's frontend slice that touches native project files. A native rebuild is required to pick up the manifest/plist and podfile changes — a Metro-only reload will not surface permission prompts or link errors. Rebuild both platforms before considering this story done.
- No JS-side permission logic belongs in this story — that's Story 6 (`7-6`). This story only gets the library installed and the native config in place so Story 6 has something to call.

## Dependencies

None on other frontend stories. Per the cross-repo ordering rule (fenzo-meta CLAUDE.md: additive backend ships before frontend consumes it), this story should not start until backend Story 4 (`7-4`, the `done_checkpoint` story) is merged and deployed — though this particular story doesn't itself call any backend endpoint, it's still gated by the epic's stated execution order (backend stories 7-1..7-4 first, then frontend 7-5..7-9).

## Testing Notes

Manual smoke test only — native permission dialogs and native-module linking aren't meaningfully unit-testable:

- Fresh install on iOS: triggering a location request (even a throwaway test call) shows the OS permission prompt with the configured `NSLocationWhenInUseUsageDescription` copy.
- Fresh install on Android: same check shows the OS `ACCESS_FINE_LOCATION` permission dialog.
- Denying permission at the OS level on either platform must not crash the app — this story only verifies the native wiring works; the graceful denial-handling *logic* (consent modal, Settings redirect, `{ error }` outcome shape) is built in Story 6, not here.
