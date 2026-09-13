# Story 2: Backend — per-step requires_location schema

## Source

- `SPEC.md` CAP-3 (per-step location requirement, independent of the job-level toggle)
- `SPEC.md` Constraints: "Any new workflow-step JSONB attribute (`requires_location`) must update BOTH the Postgres `workflow_steps_valid()` CHECK function AND the TypeScript `parseStep()` mirror in the same change, or the two silently disagree."
- `stories.yaml` id "2"

## Acceptance Criteria

1. `workflow_templates.steps` JSONB accepts an optional `requires_location` boolean per step element. Absent → treated as `true` (matches the product intent that a step requires location unless it explicitly opts out; no existing row uses this key today, so this default carries no compatibility risk).
2. The Postgres `workflow_steps_valid(p_steps JSONB)` CHECK function validates `requires_location` the same way it validates `requires_photo`/`requires_signature` today: when present, must be boolean; when absent, does not fail validation.
3. The TypeScript `parseStep()` mirror accepts and returns `requires_location` (snake_case, on the internal model — see Implementation Notes) with identical default-true semantics — never allowed to disagree with the Postgres function on what a step object looks like.
4. `stepToResponse()` maps `requires_location` → `requiresLocation` (camelCase) in the outward API response, mirroring exactly how `requiresPhoto`/`requiresSignature` are already mapped there. Without this, the field is validated and parsed internally but never reaches the frontend — Story 7's `WorkflowTemplateStep.requiresLocation` would always be `undefined`.
5. No data migration is required for the v1 seed template: since the schema default is now `true`, its existing steps (none of which carry a `requires_location` key) already read as location-required.
6. Existing workflow templates that do not set `requires_location` at all continue to pass the CHECK constraint unchanged (no existing row is invalidated by this migration).

## Implementation Notes

- **Postgres CHECK function**: `workflow_steps_valid()` was added in `supabase/migrations/20260911000003_generic_workflow_engine.sql:38-96`. This story does **not** edit that historical migration file — it adds a **new** migration that does `CREATE OR REPLACE FUNCTION workflow_steps_valid(...)` with the same signature, carrying forward every existing check (slug pattern, label, `requires_photo`/`requires_signature` booleans, `sets_status` enum, `advances_on` enum) plus the new `requires_location` boolean check (default `true` when absent).
- **TypeScript mirror**: `parseStep()` in `src/jobs/workflow-template.model.ts:36-86` builds the internal `TemplateStep` interface, whose existing fields are **snake_case** (`requires_photo`, `requires_signature`) — they mirror the raw DB JSON keys, not the outward API shape. Add `requires_location: boolean` to `TemplateStep` the same way, defaulting to `true` when the source JSON omits the key. The camelCase `requiresLocation` belongs only on `WorkflowStepResponse`/`stepToResponse()` (see AC4) — do not add a camelCase field to `TemplateStep` itself, that would break the model's established snake_case convention.
- **Hard constraint**: the CHECK function migration and the `parseStep()` change must land in the **same commit**. Shipping one without the other means the DB accepts a shape the TS layer doesn't understand (or vice versa) — SPEC.md calls this out explicitly as a silent-drift risk, not a style preference.
- No RLS changes — this story only touches the shape of an existing JSONB column, not table/row access.

## Dependencies

- Independent of Story 1 (`capture_location_on_steps` lives on `jobs`, a different table with no schema overlap) — can be built in either order relative to Story 1.
- Must land before Story 3 (RPC) and Story 4 (`WorkflowService` validation), since both need `requiresLocation` to exist on the parsed step shape to know when to require/validate location on a given step.

## Testing Notes

- CHECK constraint: inserting/updating a `workflow_templates` row with a step where `requires_location` is a string or number (not boolean) must fail the constraint.
- CHECK constraint: a step object with no `requires_location` key at all must still pass (backward compatibility).
- `parseStep()` unit tests: absent key → `requires_location === true`; `requires_location: false` → `requires_location === false`.
- `stepToResponse()` unit test: a parsed step with `requires_location: true` (or absent, defaulted true) maps to `requiresLocation: true` in the response.
- Integration: re-fetch the v1 seed template after migration and confirm the expected steps report `requiresLocation: true` in the API response (not just internally).
