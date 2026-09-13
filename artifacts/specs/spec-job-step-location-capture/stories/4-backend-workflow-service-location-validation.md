# Story 4: Backend — WorkflowService location validation

## Source

- SPEC.md CAP-2 (capture is prompted and attached when job toggle + step flag are both on)
- SPEC.md CAP-4 (step completion is never blocked by location capture failure)
- SPEC.md Constraints: "GPS accuracy is never a hard-reject condition..." and "No location-specific data-retention/deletion policy is introduced by this feature..."
- stories.yaml id "4"

## Acceptance Criteria

1. **Happy path.** `job.capture_location_on_steps = true` AND target step's `requires_location = true` AND the request carries valid `latitude`/`longitude` (in range) → the advance succeeds; the resulting `activity_logs` row's `metadata` carries the coordinates.
2. **Missing or invalid coordinates, requirement active.** Same job/step conditions as (1), but `latitude`/`longitude` are absent, or present and fail `hasInvalidCoordinates` range validation → the advance request **still succeeds** (CAP-4 — never hard-block); pass `p_location_captured: false` and a `p_reason` (e.g. `"not_provided"` or `"invalid_range"`) through to the RPC (Story 3).
3. **Low accuracy, never a gate.** Valid coordinates are provided but `accuracy > 100` (meters) → the advance succeeds; pass `p_accuracy_flagged: true` through to the RPC alongside the coordinates. This is never a hard-reject condition, per SPEC.md Constraints — accuracy is recorded, not enforced.
4. **Requirement inactive.** `job.capture_location_on_steps = false` OR the target step's `requires_location = false` (or absent) → no location validation or prompting occurs at all; the request is unaffected whether or not location fields happen to be present on it (extra fields are simply ignored, not validated).
5. **Combined signature + location step.** When a step has both `requires_signature` and `requires_location` true, this method does not care about ordering — by the time it's called, the frontend (Story 7) has already collected both the signature and the location fields; this method validates the location portion exactly as in AC1-3, independent of whether a signature also arrived.

## Implementation Notes

- **Where:** `WorkflowService.advanceWorkflowStep`. This is **new** validation logic, not a mirror of an existing pattern: `src/jobs/workflow.service.ts:57-63, 173-182` is `validateStep()` and its step-ordering guard (raises on an out-of-order step) — unrelated to requirement gating. The method's own comment (lines 50-52) states `requires_photo`/`requires_signature` are "frontend action gates, not chain filters": they are parsed and returned to the API but never enforced server-side today. This story adds the first server-side per-step content validation here, chosen because this is already where step-order guards live. Location validation is app-layer only; `advance_workflow_step` (the RPC, built in Story 3) performs no content validation of its own — that division of responsibility must hold (SPEC.md Constraints).
- **Steps:**
  1. Load `job.capture_location_on_steps` and the target step's `requires_location` (from the step's parsed JSONB, per Story 2's `parseStep()` change).
  2. If both are true: validate any provided `latitude`/`longitude` via `hasInvalidCoordinates` (reuse `src/common/utils/validate-coordinates.ts` as-is — no new validation utility). Missing or invalid coordinates never fail the request (AC 2).
  3. Accuracy is never a gate: when `accuracy > 100`, still pass the coordinates through and additionally set `p_accuracy_flagged: true` (AC 3).
  4. Pass the validated coordinates plus `p_location_captured`/`p_reason`/`p_accuracy_flagged` as applicable through to the `advance_workflow_step` RPC call added in Story 3 (six-parameter shape, not three).
- **DTO:** extend `AdvanceWorkflowDto` with optional `latitude?: number`, `longitude?: number`, `accuracy?: number`, using the same `@IsNumber() @Min()/@Max()` decorators as `StructuredAddressDto` (`src/common/dto/structured-address.dto.ts:57-69`) — lat ∈ [-90, 90], lon ∈ [-180, 180] — plus `@ApiPropertyOptional()` on each, matching this DTO's existing `step` field (already `@ApiProperty`-decorated).
- **RLS:** none needed — no new table; `activity_logs_tenant_isolation` already covers this metadata (backend-architecture.md 2.6).
- **Retention:** no bespoke retention/deletion policy for these metadata fields — they inherit whatever (currently none) governs `activity_logs` as a whole; out of scope for this story.

## Dependencies

- Story 2 (per-step `requires_location` schema) must be merged first — this story reads that flag.
- Story 3 (RPC accepts `p_latitude`/`p_longitude`/`p_accuracy`) must be merged first — this story calls that RPC shape.

## Testing Notes

- Unit-test all four acceptance-criteria scenarios above as distinct cases.
- Explicit regression guard: a fix with `accuracy > 100` must NOT block the request — assert the advance still succeeds and only `accuracyFlagged: true` is set, never a rejection/exception.
- Explicit no-op guard: when the requirement is inactive (AC 4), assert behavior is identical whether or not `latitude`/`longitude`/`accuracy` are included on the request — no validation path is entered at all.
- Cover the boundary: `accuracy` exactly `100` should NOT flag (only `> 100` does, per the spec wording "a fix worse than 100m").

## Deploy note

This story is the `done_checkpoint` in `stories.yaml` — it closes out the backend slice. Do not begin Story 5 (frontend: geolocation dependency) until this story is merged and deployed to `fenzit-be`, per the fenzo-meta CLAUDE.md cross-repo ordering rule (additive backend change ships before the frontend that consumes it).
