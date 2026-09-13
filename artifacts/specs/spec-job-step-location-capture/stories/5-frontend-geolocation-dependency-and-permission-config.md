# Story 5: Frontend — geolocation dependency + native permission config

## Source

- SPEC.md Constraints: "Must use `react-native-nitro-geolocation` (via its `/compat` API) — `fenzo-app` runs RN 0.86 with React Native's New Architecture enabled (`newArchEnabled=true`) and already depends on `react-native-nitro-modules` (via `react-native-mmkv`), so this adds no new native runtime. `react-native-geolocation-service` is bridge-only and unmaintained (last published ~4 years ago), a poor fit for this architecture; `expo-location` is unavailable (no Expo runtime)."
- frontend-architecture.md section 1 (verified: RN 0.86.0, `newArchEnabled=true`, `react-native-nitro-modules@^0.35.10` already a dependency via `react-native-mmkv`) and section 2.1.
- stories.yaml id "5".

## Acceptance Criteria

1. `react-native-nitro-geolocation` is added as a dependency via `bun add react-native-nitro-geolocation` (no npm/yarn/pnpm lockfiles introduced). `react-native-nitro-modules` is **not** added — it is already present (`^0.35.10`, pulled in transitively by `react-native-mmkv`); confirm the installed version satisfies `react-native-nitro-geolocation`'s peer requirement rather than bumping it as part of this story.
2. Android manifest (`android/app/src/main/AndroidManifest.xml`) declares `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />` (and `ACCESS_COARSE_LOCATION` alongside it, per the library's documented manifest requirements).
3. iOS `Info.plist` (`ios/<AppName>/Info.plist`) adds `NSLocationWhenInUseUsageDescription` with real, user-facing copy explaining why the app needs location (e.g. "Used to verify your location when completing job steps").
4. App builds and launches on both platforms with no new native-linking errors (autolinking should pick up the RN module; no manual pod/gradle wiring expected beyond the manifest/plist entries and a pod install on iOS).

## Implementation Notes

- **Library docs:** https://react-native-nitro-geolocation.pages.dev/guide/index.html — read this before starting; it covers installation, the `/compat` vs native API split, and native config in more depth than this story restates.
- Do **not** use `react-native-geolocation-service` — that library is bridge-only (no TurboModule/Nitro support) and was last published roughly 4 years ago; a poor and risky fit now that this app runs New Architecture. Do **not** use `expo-location` — there is no Expo runtime in this app.
- `react-native-nitro-geolocation` is built on Nitro Modules (RN 0.75+, New Architecture required for native apps). This app already satisfies both: RN 0.86.0, `newArchEnabled=true` (`android/gradle.properties:35`), and `react-native-nitro-modules@^0.35.10` already installed (via `react-native-mmkv` v4, itself a Nitro module) — so this story adds no new native JSI runtime, only the geolocation package.
- Use the library's `/compat` subpath in all later stories (`import Geolocation from 'react-native-nitro-geolocation/compat'`) — it mirrors `@react-native-community/geolocation`'s callback shape (`getCurrentPosition`, `requestAuthorization`, `watchPosition`, `clearWatch`), which is the API shape Stories 6 and 7 are written against. Do not use the library's native (non-compat) Promise-based API — that has a different call shape (`getCurrentPosition({ accuracy: { android, ios }, timeout })` returning a Promise) and would require rewriting Stories 6/7's implementation notes.
- Files touched: `android/app/src/main/AndroidManifest.xml` (permission entries), `ios/<AppName>/Info.plist` (usage-description key), `package.json` + `bun.lock` (new dependency), and an iOS `pod install` run (not a tracked file, but required after adding a native dependency).
- This is the only story in epic-7's frontend slice that touches native project files. A native rebuild is required to pick up the manifest/plist and podfile changes — a Metro-only reload will not surface permission prompts or link errors. Rebuild both platforms before considering this story done.
- No JS-side permission logic belongs in this story — that's Story 6 (`7-6`). This story only gets the library installed and the native config in place so Story 6 has something to call.

## Dependencies

None on other frontend stories. Per the cross-repo ordering rule (fenzo-meta CLAUDE.md: additive backend ships before frontend consumes it), this story should not start until backend Story 4 (`7-4`, the `done_checkpoint` story) is merged and deployed — though this particular story doesn't itself call any backend endpoint, it's still gated by the epic's stated execution order (backend stories 7-1..7-4 first, then frontend 7-5..7-9).

## Testing Notes

Manual smoke test only — native permission dialogs and native-module linking aren't meaningfully unit-testable:

- Fresh install on iOS: triggering a location request (even a throwaway test call via the `/compat` API) shows the OS permission prompt with the configured `NSLocationWhenInUseUsageDescription` copy.
- Fresh install on Android: same check shows the OS `ACCESS_FINE_LOCATION` permission dialog.
- Denying permission at the OS level on either platform must not crash the app — this story only verifies the native wiring works; the graceful denial-handling *logic* (consent modal, Settings redirect, `{ error }` outcome shape) is built in Story 6, not here.
- Confirm the existing `react-native-mmkv`-dependent features (which already exercise the Nitro runtime) still work unmodified after this dependency is added — a regression here would indicate a Nitro-modules version conflict, not a geolocation-specific bug.
