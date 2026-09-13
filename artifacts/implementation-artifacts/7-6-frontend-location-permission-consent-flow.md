---
epic: 7
story_id: "7-6"
title: "Frontend: location permission/consent flow"
status: ready-for-dev
created: 2026-09-13
updated: 2026-09-13
acceptance_criteria:
  - AC1: "New geolocation permission module created (mirrors photoPicker.ts conventions)"
  - AC2: "Granted status → proceeds directly without consent modal"
  - AC3: "Undetermined status → shows consent copy once, then requests OS permission"
  - AC4: "Denied status → shows Settings-redirect prompt instead of consent modal"
  - AC5: "Android uses PermissionsAndroid.request(ACCESS_FINE_LOCATION, ...) with consent UI"
  - AC6: "iOS uses Geolocation.requestAuthorization() from react-native-nitro-geolocation/compat"
  - AC7: "Denial outcome shape is { error: <message> }, matching photoPicker.ts pattern"
  - AC8: "No exceptions thrown; all paths result in success or error outcome"
blocking:
  - "Depends on story 7-5 (geolocation dependency must be added first)"
spec_refs:
  - "spec-job-step-location-capture/frontend-architecture.md section 2.2"
  - "spec-job-step-location-capture/stories.yaml id:6"
---

## Context

The permission flow is the second layer before GPS capture. It checks the current state once and shows UI appropriate to each state: already granted (skip consent), undetermined (show once, request), or previously denied (skip to Settings redirect).

This module mirrors `photoPicker.ts` closely but has one key difference: iOS requires an explicit authorization request for location (unlike camera, which the native picker handles implicitly).

## Changes

### 1. New file: `src/features/technicianApp/geolocation.ts`

```ts
import { PermissionsAndroid, Platform } from 'react-native';
import { Geolocation } from 'react-native-nitro-geolocation/compat';

export interface LocationPermissionOutcome {
  status: 'granted' | 'denied' | 'undetermined';
  error?: string;
}

export const LOCATION_PERMISSION_MESSAGE =
  'Location required to verify step completion';

export async function getLocationPermission(): Promise<LocationPermissionOutcome> {
  if (Platform.OS === 'android') {
    const status = await PermissionsAndroid.check(
      PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION
    );
    if (status) return { status: 'granted' };
    
    const granted = await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
      {
        title: 'Location Permission',
        message: LOCATION_PERMISSION_MESSAGE,
        buttonPositive: 'Allow',
        buttonNegative: 'Cancel',
      }
    );
    
    return {
      status: granted === PermissionsAndroid.RESULTS.GRANTED ? 'granted' : 'denied',
      ...(granted !== PermissionsAndroid.RESULTS.GRANTED && {
        error: LOCATION_PERMISSION_MESSAGE,
      }),
    };
  }
  
  // iOS
  const result = await Geolocation.requestAuthorization('whenInUse');
  return {
    status: result === 'granted' ? 'granted' : 'denied',
    ...(result !== 'granted' && { error: LOCATION_PERMISSION_MESSAGE }),
  };
}
```

## Testing

- [ ] Manual (Android): Granted state skips modal, Undetermined shows consent, Denied redirects to Settings
- [ ] Manual (iOS): Same flow; verify Geolocation.requestAuthorization is called
- [ ] Manual: Error outcome shape matches { error: <message> }

## Links

- Spec: `artifacts/specs/spec-job-step-location-capture/frontend-architecture.md section 2.2`
- Reference: `src/features/technicianApp/photoPicker.ts` (pattern to mirror)
