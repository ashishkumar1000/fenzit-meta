---
epic: 7
story_id: "7-9"
title: "Frontend: NewJobScreen location toggle"
status: done
superseded: "2026-09-13 — commit d4ec3c9 removed the job-level toggle from NewJobScreen; step-level requires_location is the single source of truth. Historical record only."
created: 2026-09-13
updated: 2026-09-13
acceptance_criteria:
  - AC1: "NewJobScreen has a single toggle switch for location capture"
  - AC2: "Label reads 'Require technician location when completing steps' (or similar)"
  - AC3: "Toggle is wired to captureLocationOnSteps field in create-job payload"
  - AC4: "Toggle is ON (true) by default"
  - AC5: "Toggle value is included in CreateJobRequest when job is created"
  - AC6: "No location-picker UI is added (toggle only, no coordinate picking)"
blocking: []
spec_refs:
  - "spec-job-step-location-capture/frontend-architecture.md section 2.5"
  - "spec-job-step-location-capture/stories.yaml id:9"
---

## Context

This is the final story — a feature-complete checkpoint. It adds the user-facing toggle to NewJobScreen so owners can opt out of location capture per job. No location-picker UI is added (none exists in the app for jobs today, and none is needed for this feature — the feature is a boolean flag, not coordinates).

## Changes

### 1. Update NewJobScreen component
File: `src/features/newJob/NewJobScreen.tsx`

Add a toggle control (likely inside the form section, near other toggles/switches if any). Rough pattern:

```tsx
import { Switch } from 'react-native';

export function NewJobScreen() {
  const [draft, setDraft] = useState({
    customerId: '',
    skillIds: [],
    targetDate: '',
    captureLocationOnSteps: true,  // NEW — default ON
  });

  // Inside render, add toggle:
  <View style={styles.toggleContainer}>
    <Text style={styles.label}>
      Require technician location when completing steps
    </Text>
    <Switch
      value={draft.captureLocationOnSteps}
      onValueChange={(val) =>
        setDraft((prev) => ({ ...prev, captureLocationOnSteps: val }))
      }
    />
  </View>

  // In the create-job call:
  const payload: CreateJobRequest = {
    customerId: draft.customerId,
    skillIds: draft.skillIds,
    targetDate: draft.targetDate,
    captureLocationOnSteps: draft.captureLocationOnSteps,  // NEW
  };
  await jobService.createJob(payload);
}
```

### 2. Styling
- Align toggle with other form controls on the screen
- Use design-system spacing/tokens for consistency
- Label text color/weight should match other form labels

## Testing

- [ ] Manual: Toggle appears on NewJobScreen
- [ ] Manual: Toggle is ON by default
- [ ] Manual: Toggling ON/OFF updates internal state
- [ ] Manual: Job created with captureLocationOnSteps: true when toggle is ON
- [ ] Manual: Job created with captureLocationOnSteps: false when toggle is OFF
- [ ] Manual: No other form functionality is broken by the change

## Links

- Spec: `artifacts/specs/spec-job-step-location-capture/frontend-architecture.md section 2.5`
- Reference: `src/features/newJob/NewJobScreen.tsx` (file to modify)
