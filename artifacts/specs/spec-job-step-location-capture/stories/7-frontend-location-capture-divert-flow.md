# Story 7: Frontend — location-capture divert flow

## Source

- SPEC.md CAP-2 (capture flow attaches lat/long/accuracy to the advance request)
- SPEC.md CAP-4 (step completion is never blocked by capture failure)
- SPEC.md Constraints — the divert-then-advance shape must be identical to the existing signature-capture pattern (`useWorkflowAdvance.ts`: `requiresSignature` → navigate away before posting)
- stories.yaml id "7"

## Acceptance Criteria

1. `WorkflowTemplateStep` gains `requiresLocation: boolean`, mirroring the existing `requiresPhoto`/`requiresSignature` fields.
2. In `useWorkflowAdvance.ts`'s `advance` callback, a step with `requiresLocation: true` (and no signature requirement) diverts to a dedicated capture screen instead of calling `advanceWorkflow` directly — the branch is structurally identical to the existing `requiresSignature` branch, not an inline capture inside the callback.
3. The capture screen runs, in order: permission check → GPS fetch (hard 15s timeout) → on success, calls `advanceWorkflow` with `{ latitude, longitude, accuracy }` attached.
4. On any capture failure (permission denied, GPS unavailable, 15s timeout elapsed), the screen still calls `advanceWorkflow` — without coordinates, or with a low-accuracy fix as-is — per CAP-4. Capture failure never stalls the technician's ability to advance the step.
5. Steps where `requiresLocation` is false (or absent) and `requiresSignature` is also false (or absent) are completely unaffected — no divert, no capture screen, behavior identical to today.
6. **Combined requirement.** A step with both `requiresSignature: true` and `requiresLocation: true` requires both captures before advancing: the technician is diverted to signature capture first, and only after a successful signature capture is the technician diverted onward to location capture; `advanceWorkflow` is called exactly once at the end, carrying both the signature reference and the location fields (or their CAP-4 graceful-failure equivalents). Neither requirement silently pre-empts the other.

## Implementation Notes

Add the divert branch in `useWorkflowAdvance.ts`'s `advance` callback. The signature branch now carries a flag telling `SignatureScreen` whether to continue on to location capture afterward, instead of calling `advanceWorkflow` itself:

```ts
if (targetStep?.requiresSignature) {
  onCaptureSignature(targetStep.key, { thenRequiresLocation: !!targetStep.requiresLocation });
  return;
}
if (targetStep?.requiresLocation) {
  onCaptureLocation(targetStep.key);
  return;
}
```

Placement and structure must match the signature branch precisely — same early-return shape, same "hand off to a callback prop, let the destination screen own the rest of the flow" pattern. Do not fold location capture logic into `advance` itself.

`SignatureScreen` (whichever container currently ends its flow by calling `advanceWorkflow` — confirm by reading its current implementation before deciding how to thread the new flag through) must check `thenRequiresLocation`: if `true`, after a successful signature capture it navigates to `LocationCaptureScreen` instead of calling `advanceWorkflow` itself; if `false`/absent, its existing behavior (capture → upload → advance directly) is unchanged. `LocationCaptureScreen` is the one that finally calls `advanceWorkflow` in both the combined case (carrying the signature reference it was handed, plus location fields) and the location-only case (location fields alone).

A new `LocationCaptureScreen` (or an inline sheet, matching whichever container the signature flow currently uses) owns the full sequence: permission check (via Story 6's permission module) → `Geolocation.getCurrentPosition(...)` (imported from `react-native-nitro-geolocation/compat`, Story 5's dependency) with a 15-second timeout → on success, call `advanceWorkflow` (Story 8) with the fix; on failure, call `advanceWorkflow` with no location fields and let the backend record the omission (backend Story 4 already handles missing/invalid location as non-blocking).

The 15-second GPS timeout is a hard requirement — cited in frontend-architecture.md as a field-service norm, not a suggestion to tune later.

Low-accuracy fixes (>100m, per SPEC.md Constraints) are **not** a capture-screen concern — pass whatever `accuracy` the GPS API reports straight through; the backend (Story 4) is what sets `accuracyFlagged`, not this screen.

## Dependencies

- Story 5 (geolocation dependency + native permission config) must land first — this screen calls the geolocation library directly.
- Story 6 (permission/consent flow) must land first — the capture screen's permission check step is Story 6's module, not reimplemented here.
- Story 4 (backend `WorkflowService` location validation) must be merged and deployed before this story is exercised end-to-end — the advance call this screen makes now carries location fields the backend interprets; per the fenzo-meta cross-repo ordering rule, the additive backend change ships first.
- Story 8 (wire location into `advanceWorkflow` + job types) must land alongside or before this story — the capture screen calls the extended `advanceWorkflow` signature.

## Testing Notes

- Divert triggers when `targetStep.requiresLocation` is `true` and `requiresSignature` is falsy; a step with both flags falsy takes the pre-existing path unchanged (no divert, no capture screen render).
- Successful GPS fetch attaches all three fields (`latitude`, `longitude`, `accuracy`) to the `advanceWorkflow` call.
- Simulated GPS timeout (15s elapsed, no fix) still results in `advanceWorkflow` being called (CAP-4) — verify the request proceeds without coordinates rather than hanging or erroring out to the user.
- Simulated permission denial still results in `advanceWorkflow` being called (CAP-4) — same non-blocking behavior as timeout.
- A low-accuracy fix (mocked `accuracy > 100`) is passed through unchanged to `advanceWorkflow` — this screen does not gate or warn on accuracy; that is backend-side (Story 4).
- Combined case: a step with both `requiresSignature` and `requiresLocation` true → `advance` diverts to signature capture with `thenRequiresLocation: true`; after a successful signature capture, `advanceWorkflow` is NOT yet called; the flow proceeds to `LocationCaptureScreen`; `advanceWorkflow` is called exactly once, at the very end, with both the signature reference and the location fields present.
- Regression: existing `requiresSignature`-only steps (with `requiresLocation` false/absent) continue to behave exactly as before this story — signature capture still calls `advanceWorkflow` directly, no location divert. Steps with neither flag are also unaffected.
