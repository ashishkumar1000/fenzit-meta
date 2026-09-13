# Story 6: Frontend — location permission/consent flow

## Source

- SPEC.md → Constraints: "The permission consent modal shows at most once per install — only while permission status is `undetermined`. Already-granted or already-denied states must never re-trigger it (denied → Settings redirect instead)."
- stories.yaml → id `"6"`, "Frontend: location permission/consent flow"

## Acceptance Criteria

1. Permission status `granted` → the flow proceeds directly to GPS fetch; no consent modal is ever shown.
2. Permission status `undetermined` → the consent copy ("Location required to verify step completion") is shown exactly once, then the OS permission request is made.
3. Permission status `denied` (i.e. previously denied) → the consent modal is skipped entirely; a Settings-redirect prompt is shown instead, pointing the technician to the OS app settings screen.
4. A denial outcome (OS request rejected, or previously-denied path taken) is returned as `{ error: <message> }` — never a thrown exception. This matches `photoPicker.ts`'s outcome shape, not the raw RN camera picker's throw-based behavior.
5. The consent modal never re-appears after the first `undetermined` → request cycle for a given install, regardless of the OS result.

## Implementation Notes

- New module, same directory and conventions as `src/features/technicianApp/photoPicker.ts:98-111`:
  - Check current permission status **first**, before showing any UI. Android: `PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION)`. iOS: the chosen geolocation library's status check (e.g. `Geolocation.requestAuthorization` return, or a dedicated status getter if `react-native-geolocation-service` exposes one).
  - `granted` → return immediately, skip all UI.
  - `undetermined` → show the consent copy once, then:
    - Android: `PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION, { title, message, buttonPositive: 'Allow', buttonNegative: 'Cancel' })`, same shape as the camera permission request in `photoPicker.ts`.
    - iOS: an **explicit** authorization call is required here — unlike the camera flow, which relies entirely on the native picker library reading `Info.plist` implicitly. This is the one place the location flow diverges from the `photoPicker.ts` pattern; call it out inline as a comment so a future reader isn't confused by the asymmetry.
  - `denied` (previously) → do not show the consent modal; show a Settings-redirect prompt instead (e.g. `Linking.openSettings()` on tap).
  - On any denial path, return `{ error: <message> }` from the module function — never throw. Export a named denial-copy constant, mirroring `CAMERA_PERMISSION_MESSAGE` (e.g. `LOCATION_PERMISSION_MESSAGE`).
- **Android "never ask again" nuance:** `PermissionsAndroid.check()` only returns a boolean (granted or not) — it cannot distinguish "denied, can ask again" from "denied, don't ask again." That distinction only appears in the *result* of a `PermissionsAndroid.request()` call (`RESULTS.DENIED` vs `RESULTS.NEVER_ASK_AGAIN`). So: the first time `request()` returns `NEVER_ASK_AGAIN`, persist that fact locally (MMKV, matching this app's existing local-storage convention) under a dedicated key. On subsequent opens, treat "previously denied" as: stored `NEVER_ASK_AGAIN` flag set OR a plain not-granted status after the consent flow has already run once — either way, route to the Settings-redirect path (re-requesting via `PermissionsAndroid.request()` is a no-op once the OS has returned `NEVER_ASK_AGAIN`, so there is no separate "denied but askable" branch to build — this module only needs the one persisted flag to know it should stop calling `request()` and show Settings instead).
- Keep this module focused on permission/consent only — GPS fetch and the capture screen belong to Story 7.

## Dependencies

- Story 5 (add `react-native-geolocation-service` dependency + native permission config) must land first — this module calls into that library and assumes the manifest/`Info.plist` entries already exist.

## Testing Notes

- Unit test each permission-status branch in isolation (mock the status check):
  - `granted` → no modal rendered/shown, flow proceeds straight through.
  - `undetermined` → consent copy shown exactly once, then the OS request fires.
  - `denied` → consent modal never shown; Settings-redirect prompt shown instead.
- Unit test: a mocked `request()` result of `NEVER_ASK_AGAIN` persists the flag (assert the MMKV write); a subsequent call with the flag already set skips `request()` entirely and goes straight to the Settings-redirect prompt.
- Assert the denial outcome shape is `{ error: <message> }` in every failure path — never a thrown exception (test should catch a throw as a failure, not an expected outcome).
- Assert the Settings-redirect path and the consent-modal path are rendered/triggered independently — a test asserting one must not also see the other fire.
