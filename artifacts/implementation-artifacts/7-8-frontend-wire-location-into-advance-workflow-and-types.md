---
epic: 7
story_id: "7-8"
title: "Frontend: wire location into advanceWorkflow + job types"
status: ready-for-dev
created: 2026-09-13
updated: 2026-09-13
acceptance_criteria:
  - AC1: "advanceWorkflow() signature extended to accept optional location param"
  - AC2: "Location spread into request body as latitude, longitude, accuracy"
  - AC3: "Existing keyRef idempotency pattern reused unchanged"
  - AC4: "CreateJobRequest type extended with captureLocationOnSteps: boolean field"
  - AC5: "ApiJob type extended with captureLocationOnSteps: boolean field"
  - AC6: "No new retry/queue mechanism added (reuse keyRef as-is per SPEC constraints)"
blocking:
  - "Depends on stories 7-5, 7-6, 7-7 (location infrastructure)"
spec_refs:
  - "spec-job-step-location-capture/frontend-architecture.md sections 2.4 and 2.6"
  - "spec-job-step-location-capture/stories.yaml id:8"
---

## Context

This story wires location data into the API layer and extends the job types to support the capture_location_on_steps toggle. It's a fairly small change — extending existing function signatures and types to carry location data alongside the existing idempotency pattern.

## Changes

### 1. Update advanceWorkflow function
File: `src/services/resources/jobs.ts`

```ts
interface LocationData {
  latitude: number | null;
  longitude: number | null;
  accuracy: number | null;
}

async function advanceWorkflow(
  id: string,
  step: string,
  idempotencyKey: string,
  location?: LocationData
): Promise<ApiJob> {
  const res = await apiClient.post<ApiJob>(
    `/jobs/${id}/workflow`,
    { step, ...(location ?? {}) },
    { headers: { 'X-Idempotency-Key': idempotencyKey } }
  );
  return res.data;
}
```

### 2. Extend CreateJobRequest type
File: `src/services/resources/jobs.ts`

```ts
export interface CreateJobRequest {
  customerId: string;
  skillIds: string[];
  targetDate: string;
  status?: string;
  captureLocationOnSteps?: boolean;  // NEW (default true on backend, but optional in request)
}
```

### 3. Extend ApiJob type
File: `src/services/resources/jobs.ts`

```ts
export interface ApiJob {
  // ... existing fields
  captureLocationOnSteps: boolean;  // NEW
}
```

### 4. Update LocationCaptureScreen to use extended advanceWorkflow
File: `src/features/technicianApp/LocationCaptureScreen.tsx`

Ensure calls match new signature:
```ts
await advanceWorkflow(jobId, stepKey, idempotencyKey, {
  latitude: position.coords.latitude,
  longitude: position.coords.longitude,
  accuracy: position.coords.accuracy,
});
```

## Testing

- [ ] Unit: advanceWorkflow accepts and passes location data in POST body
- [ ] Unit: advanceWorkflow spreads location data correctly (no nesting)
- [ ] Unit: idempotencyKey is still passed and reused unchanged
- [ ] Manual: CreateJobRequest can be created with/without captureLocationOnSteps
- [ ] Manual: ApiJob response parses captureLocationOnSteps correctly

## Links

- Spec: `artifacts/specs/spec-job-step-location-capture/frontend-architecture.md sections 2.4 and 2.6`
- Reference: `src/services/resources/jobs.ts` (current advanceWorkflow implementation)
