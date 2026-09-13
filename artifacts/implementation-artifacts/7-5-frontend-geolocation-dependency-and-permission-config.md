---
epic: 7
story_id: "7-5"
title: "Frontend: geolocation dependency + native permission config"
status: ready-for-dev
created: 2026-09-13
updated: 2026-09-13
acceptance_criteria:
  - AC1: "react-native-nitro-geolocation added to fenzo-app package.json via bun"
  - AC2: "ACCESS_FINE_LOCATION permission added to Android manifest (android/app/src/main/AndroidManifest.xml)"
  - AC3: "NSLocationWhenInUseUsageDescription added to iOS Info.plist (ios/FenzoApp/Info.plist)"
  - AC4: "Dependency builds successfully on both Android and iOS native runtimes"
  - AC5: "No console errors or warnings from geolocation imports in app initialization"
blocking:
  - "Backend stories 7-1 to 7-4 must be merged and deployed first (cross-repo ordering rule)"
spec_refs:
  - "spec-job-step-location-capture/frontend-architecture.md section 2.1"
  - "spec-job-step-location-capture/stories.yaml id:5"
---

## Context

Geolocation is the foundation for all GPS location capture on the frontend. This story adds the library dependency and configures native permissions so that subsequent stories (7-6 permission flow, 7-7 capture flow) can call the API without runtime permission errors.

react-native-nitro-geolocation is chosen because:
- fenzo-app already uses New Architecture (required by this library)
- Already depends on react-native-nitro-modules (no new native setup)
- Actively maintained; unmaintained alternative (react-native-geolocation-service) and Expo-only (expo-location) ruled out

## Changes

### 1. Add dependency to fenzo-app
- Run: `cd workspace/core/frontend/fenzo-app && bun add react-native-nitro-geolocation`
- Verify `bun.lock` updated and build passes
- No version pinning needed (use bun's default latest semver)

### 2. Android manifest permission
- File: `workspace/core/frontend/fenzo-app/android/app/src/main/AndroidManifest.xml`
- Add:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```
- Place before closing `</manifest>` tag

### 3. iOS Info.plist config
- File: `workspace/core/frontend/fenzo-app/ios/FenzoApp/Info.plist`
- Add:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Fenzo uses your location to record where you complete technician jobs.</string>
```
- Paste into the root `<dict>` block

### 4. Build verification
- Android: `cd workspace/core/frontend/fenzo-app && bun run android` (or validate via gradle)
- iOS: `cd workspace/core/frontend/fenzo-app && bun run ios`
- No build errors; app launches without native errors

## Testing

- [ ] Manual: iOS app builds and launches without permission errors
- [ ] Manual: Android app builds and launches without permission errors
- [ ] Manual: No console errors on app startup related to geolocation

## Links

- Library docs: https://react-native-nitro-geolocation.pages.dev/guide/index.html
- Spec: `artifacts/specs/spec-job-step-location-capture/frontend-architecture.md`
