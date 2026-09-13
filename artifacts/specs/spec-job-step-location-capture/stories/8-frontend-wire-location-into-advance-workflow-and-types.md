# Story 8: Frontend — wire location into advanceWorkflow + job types

## Source

- SPEC.md Constraints: "No new offline-queue engine — reuse the existing per-action idempotency-key (`keyRef`) + inline-retry convention already in `useWorkflowAdvance.ts`."
- stories.yaml id "8" ("Frontend: wire location into advanceWorkflow + job types")

## Acceptance Criteria

1. `advanceWorkflow()` accepts an optional fourth parameter `location: { latitude: number; longitude: number; accuracy: number }` and, when present, spreads its three fields directly into the POST body alongside `step`.
2. When `location` is omitted (steps that don't require it), the POST body contains only `{ step }` — no location keys are sent, not even as `undefined`/`null`.
3. The existing `keyRef` idempotency-key mechanism in `useWorkflowAdvance.ts` is reused completely unchanged: the header name, the mint-once-reuse-until-server-answers lifecycle, and the "clear only on genuine server response" rule all stay exactly as they are today. No new retry or queue logic is added for the location payload.
4. `CreateJobRequest` and `ApiJob` both gain `captureLocationOnSteps: boolean`, mirroring the backend DTO field added in Story 1 (job-level location-capture toggle) so the value round-trips through job creation and job reads.

## Implementation Notes

File: `src/services/resources/jobs.ts` (`CreateJobRequest` lines 73-93, `ApiJob` lines 135-200, `advanceWorkflow` lines 408-413).

Signature change (frontend-architecture.md §2.4):

```ts
async function advanceWorkflow(
  id: string, step: string, idempotencyKey: string,
  location?: { latitude: number; longitude: number; accuracy: number }
): Promise<ApiJob> {
  const res = await apiClient.post<ApiJob>(`/jobs/${id}/workflow`,
    { step, ...(location ?? {}) },
    { headers: { 'X-Idempotency-Key': idempotencyKey } });
  return res.data;
}
```

`{ ...(location ?? {}) }` is what gives AC2 for free — spreading `undefined` via `?? {}` adds no keys, so callers that never pass `location` (every existing call site) see zero body change.

The `keyRef` primitive itself lives in `useWorkflowAdvance.ts`, not in this file — this story only changes what `advanceWorkflow` accepts and forwards. Do not touch `keyRef`'s mint/clear lifecycle; the hook change that actually passes a `location` value through belongs to Story 7 (the capture screen), not this story.

`CreateJobRequest`/`ApiJob` are plain type additions — no runtime logic, just the new boolean field so TypeScript keeps job-creation and job-read call sites honest about the field the backend now serializes (Story 1).

## Dependencies

- None on Story 7 — this story is not blocked by it. (Note, not a dependency: Story 7 is the eventual *caller* that will pass a real `location` object into `advanceWorkflow` once built; this story only adds the capability and can be built and merged independently, before or after Story 7.)
- Story 4 (backend `WorkflowService` location validation) must already be deployed and accepting `latitude`/`longitude`/`accuracy` on the advance-workflow endpoint, per the cross-repo ordering rule (BE ships before FE).

## Testing Notes

- Unit test: calling `advanceWorkflow(id, step, key)` with no fourth argument produces a POST body of exactly `{ step }` — confirms the omitted-location path never leaks stray keys.
- Unit test: calling `advanceWorkflow(id, step, key, { latitude, longitude, accuracy })` produces a POST body with all four fields (`step` plus the three location fields) at the top level, not nested under a `location` key.
- Type-check only (no new runtime behavior): `CreateJobRequest` and `ApiJob` literals/fixtures across the test suite compile with `captureLocationOnSteps: boolean` added; update any fixture that constructs these types with all fields explicit.
