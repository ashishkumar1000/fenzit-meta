---
epic: 7
story_id: "7-7"
title: "Frontend: location-capture divert flow"
status: ready-for-dev
created: 2026-09-13
updated: 2026-09-13
acceptance_criteria:
  - AC1: "WorkflowTemplateStep type extended with requiresLocation: boolean field"
  - AC2: "useWorkflowAdvance.ts advance callback checks requiresLocation and diverts to LocationCaptureScreen"
  - AC3: "Divert logic mirrors existing requiresSignature pattern (not inline capture)"
  - AC4: "LocationCaptureScreen created with permission check → GPS fetch → advance flow"
  - AC5: "GPS fetch uses Geolocation.getCurrentPosition() with 15s timeout"
  - AC6: "On success or graceful failure (CAP-4), LocationCaptureScreen calls advanceWorkflow"
  - AC7: "Step with both requiresSignature and requiresLocation chains both captures"
  - AC8: "SignatureScreen checks thenRequiresLocation flag and chains to LocationCaptureScreen if true"
blocking:
  - "Depends on stories 7-5 (geolocation library) and 7-6 (permission flow)"
spec_refs:
  - "spec-job-step-location-capture/frontend-architecture.md section 2.3"
  - "spec-job-step-location-capture/stories.yaml id:7"
---

## Context

The location-capture divert flow is the third layer. It intercepts steps that require location and diverts them to a dedicated capture screen (mirroring the signature flow pattern), where the app checks permissions, fetches GPS data, and advances on success or graceful failure.

Two key patterns from the spec:
1. **Divert-then-advance**: A step requiring location doesn't call advanceWorkflow directly; instead, it diverts to LocationCaptureScreen, which owns the flow and calls advance at the end.
2. **Chaining**: A step with both requiresSignature and requiresLocation must complete both captures before advancing. SignatureScreen checks a flag and chains to LocationCaptureScreen on success.

## Changes

### 1. Extend WorkflowTemplateStep type
File: `src/services/resources/jobs.ts`

Add field to WorkflowTemplateStep interface:
```ts
export interface WorkflowTemplateStep {
  key: string;
  label: string;
  requiresPhoto: boolean;
  requiresSignature: boolean;
  requiresLocation: boolean;  // NEW
  setsStatus: string | null;
  advancesOn: string | null;
}
```

### 2. Update useWorkflowAdvance.ts divert logic
File: `src/features/technicianApp/useWorkflowAdvance.ts`

In the advance callback, add divert checks:
```ts
const advance = useCallback(async (step: string) => {
  if (!jobId || pendingRef.current) return;
  const targetStep = detail?.workflowTemplate?.steps?.find(s => s.key === step);
  
  if (targetStep?.requiresSignature) {
    onCaptureSignature(targetStep.key, { thenRequiresLocation: !!targetStep.requiresLocation });
    return;
  }
  
  if (targetStep?.requiresLocation) {
    onCaptureLocation(targetStep.key);
    return;
  }
  
  // ... existing advance logic
}, [jobId, detail, onCaptureSignature, onCaptureLocation]);
```

### 3. Update SignatureScreen
File: `src/features/technicianApp/SignatureScreen.tsx` (or equivalent signature capture container)

Add flag handling:
```ts
interface SignatureCaptureParams {
  stepKey: string;
  thenRequiresLocation?: boolean;
}

// After successful signature capture:
if (thenRequiresLocation) {
  navigation.navigate('LocationCapture', { stepKey });
} else {
  // ... existing advance workflow call
}
```

### 4. Create LocationCaptureScreen
File: `src/features/technicianApp/LocationCaptureScreen.tsx`

High-level flow:
```ts
export function LocationCaptureScreen({ route, navigation }: ...) {
  const { stepKey, signatureRef } = route.params;
  
  useEffect(() => {
    captureLocation();
  }, []);
  
  async function captureLocation() {
    // 1. Check permission (uses geolocation.ts from 7-6)
    const permOutcome = await getLocationPermission();
    if (permOutcome.status !== 'granted') {
      setError(permOutcome.error || 'Permission denied');
      return;
    }
    
    // 2. Fetch GPS (15s timeout)
    try {
      const position = await new Promise((resolve, reject) => {
        const timeout = setTimeout(
          () => reject(new Error('GPS fetch timeout')),
          15000
        );
        Geolocation.getCurrentPosition(
          (pos) => { clearTimeout(timeout); resolve(pos); },
          (err) => { clearTimeout(timeout); reject(err); }
        );
      });
      
      // 3. Advance with location
      await advanceWorkflow(jobId, stepKey, idempotencyKey, {
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
        accuracy: position.coords.accuracy,
      });
      
      navigation.goBack();
    } catch (err) {
      // CAP-4: Graceful failure — flag but don't block
      await advanceWorkflow(jobId, stepKey, idempotencyKey, {
        latitude: null,
        longitude: null,
        accuracy: null,
      });
      navigation.goBack();
    }
  }
}
```

## Testing

- [ ] Manual: Step with requiresLocation only diverts to LocationCaptureScreen
- [ ] Manual: Step with both requiresSignature and requiresLocation chains correctly
- [ ] Manual: GPS fetch with 15s timeout; graceful failure on timeout
- [ ] Manual: On success or timeout, advance is called with location data

## Links

- Spec: `artifacts/specs/spec-job-step-location-capture/frontend-architecture.md section 2.3`
- Reference: `src/features/technicianApp/SignatureScreen.tsx` (pattern to mirror)
- Reference: `src/features/technicianApp/useWorkflowAdvance.ts` (divert integration point)
