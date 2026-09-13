# Backend Architecture — fenzit-be

Verified against current code (see file paths cited). Every change below is additive; no existing endpoint contract breaks.

## 1. Current state (verified)

**`jobs` table** — final columns after all migrations (confirmed against `JOB_COLUMNS` in `src/jobs/jobs.service.ts:213`, which selects flat columns plus the related `skills(id, name)` and `workflow_templates(version, steps)` via PostgREST relation syntax — `workflow_template_id`/`workflow_template_version` are real columns on the table but are not selected by name in that constant):
`id, tenant_id, job_number, customer_id, technician_id, service_location, scheduled_start, scheduled_end, status, current_step, priority, description, notes_for_technician, created_at, updated_at, completed_at, skill_id, workflow_template_id, workflow_template_version`

No location columns exist. `service_location` is free-text only.

**`workflow_templates.steps`** JSONB, one array element example (`20260911000002_workflow_templates_skill_tagged_jobs.sql:58`):
```json
{"key": "photos_uploaded", "label": "Photos Uploaded", "requires_photo": true, "requires_signature": false, "sets_status": null, "advances_on": "photo_confirm"}
```
Shape enforced by a Postgres CHECK function `workflow_steps_valid(p_steps JSONB)` (added in `20260911000003_generic_workflow_engine.sql:38-96`), wired via `ALTER TABLE workflow_templates ADD CONSTRAINT workflow_templates_steps_shape CHECK (workflow_steps_valid(steps))`. It requires: unique slug key (`^[a-z0-9_]{1,64}$`), non-empty label, boolean `requires_photo`/`requires_signature`, `sets_status` ∈ {null, 'in_progress', 'completed'}, `advances_on` ∈ {null, 'photo_confirm'}.

Mirrored independently in TypeScript by `parseStep()` in `src/jobs/workflow-template.model.ts:36-86`.

**`advance_workflow_step` RPC** — latest definition, `supabase/migrations/20260909000003_rpc_notify_owner_on_advance.sql:11-87`:
```sql
CREATE OR REPLACE FUNCTION advance_workflow_step(
  p_job_id UUID, p_tenant_id UUID, p_actor_id UUID,
  p_step TEXT, p_new_status TEXT, p_expected_current_step TEXT
) RETURNS SETOF jobs ...
```
Does: tenant-scoped row lock, status/expected-step guards (raises `PT409` on conflict), updates `current_step`/`status`/`completed_at`, inserts into `activity_logs` (`event_type = 'step_' || p_step`), inserts a `notifications` row for the owner. **No content validation of any kind happens in this RPC** — photo/signature requirement checks happen entirely in NestJS before this is called.

**`activity_logs`** schema (`20260621000002_create_jobs.sql:42-59`):
```sql
CREATE TABLE activity_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  actor_id UUID NOT NULL REFERENCES users(id),
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```
`metadata` is already used for structured per-event payloads elsewhere (e.g. `job_reassigned`, `confirm_attachment`). RLS: `activity_logs_tenant_isolation`, `FOR ALL USING/WITH CHECK (tenant_id = (auth.jwt()->>'tenantId')::uuid)` — this is the standard tenant-isolation shape every tenant-scoped table in this repo uses; a new column/table should reuse it verbatim.

**`customers`** table already has `latitude`/`longitude`/`formatted_address`/`pincode`/`place_id` (all nullable `DOUBLE PRECISION`/`TEXT`, added `20260905000005_add_customer_structured_address.sql`). App-layer range validation exists: `src/common/dto/structured-address.dto.ts:57-69` (`@IsNumber() @Min(-90)/@Max(90)` lat, `@Min(-180)/@Max(180)` lon) and a reusable guard `src/common/utils/validate-coordinates.ts` (`hasInvalidCoordinates`).

**No haversine/distance/geofence utility exists anywhere in the backend** (verified by repo-wide grep). Confirms CAP geofencing is out of scope (see SPEC.md Non-goals).

**Historical precedent**: `jobs` used to carry `require_completion_photo`/`require_completion_signature` as job-level booleans — `require_completion_photo` was in the original `20260621000002` schema, `require_completion_signature` was added later by a separate migration (`20260905000001_add_jobs_require_completion_signature.sql`) — both dropped together in `20260911000003` in favor of the current per-step JSONB flags. The job-level toggle this feature adds is, in effect, reviving that same pattern for one new requirement type (location), on purpose, per the MVP scope decision.

**`CreateJobDto`** (`src/jobs/dto/create-job.dto.ts:17-83`) and **`AdvanceWorkflowDto`** (`src/jobs/dto/advance-workflow.dto.ts`, only field `step: string` matched against `STEP_KEY_PATTERN = /^[a-z0-9_]{1,64}$/`) currently have zero location fields.

## 2. Changes required

### 2.1 Migration: add job-level toggle
```sql
ALTER TABLE jobs ADD COLUMN capture_location_on_steps BOOLEAN NOT NULL DEFAULT true;
```
No lat/long columns on `jobs` itself — CAP-1/CAP-2 don't need the job to store its own coordinates, only the toggle.

### 2.2 Migration: extend step JSONB validation
Update `workflow_steps_valid()` to accept an additional optional-with-default boolean `requires_location` (default `true` if absent) alongside the existing `requires_photo`/`requires_signature` checks. No existing row uses this key today, so defaulting absent to `true` carries no compatibility risk and matches the product intent that each step requires location unless a step explicitly opts out. Update `parseStep()` in `workflow-template.model.ts` in the same change (same default) — these two must never drift.

Seed data: no explicit data migration is needed for the v1 template — since the schema default is now `true`, its existing steps (which carry no `requires_location` key) already read as location-required. A step should only set `requires_location: false` explicitly if it is meant to opt out.

### 2.3 RPC: extend `advance_workflow_step`
Add six new optional parameters: `p_latitude DOUBLE PRECISION DEFAULT NULL`, `p_longitude DOUBLE PRECISION DEFAULT NULL`, `p_accuracy DOUBLE PRECISION DEFAULT NULL`, `p_location_captured BOOLEAN DEFAULT NULL`, `p_reason TEXT DEFAULT NULL`, `p_accuracy_flagged BOOLEAN DEFAULT NULL`. The last three exist because `WorkflowService` (2.4) needs somewhere to persist the "why" when location wasn't captured, or the low-accuracy flag, and the RPC performs no content validation of its own — it only inserts whatever `WorkflowService` already decided. Extend the existing `activity_logs` insert to merge these into `metadata`:
```sql
INSERT INTO activity_logs (job_id, tenant_id, event_type, actor_id, metadata)
VALUES (
  p_job_id, p_tenant_id, 'step_' || p_step, p_actor_id,
  CASE WHEN p_latitude IS NOT NULL AND p_longitude IS NOT NULL THEN
    jsonb_strip_nulls(jsonb_build_object(
      'latitude', p_latitude, 'longitude', p_longitude, 'accuracy', p_accuracy,
      'locationCaptured', p_location_captured, 'reason', p_reason,
      'accuracyFlagged', p_accuracy_flagged
    ))
  WHEN p_location_captured IS NOT NULL THEN
    jsonb_strip_nulls(jsonb_build_object('locationCaptured', p_location_captured, 'reason', p_reason))
  ELSE NULL END
);
```
`p_latitude`/`p_longitude` must arrive together or not at all — a partial pair (one set, one NULL) is treated as no coordinates, falling through to the `p_location_captured`-only branch. `jsonb_strip_nulls` drops any of the optional flag/reason keys that weren't supplied, so the object never carries a stray `null` field. No other RPC logic changes — the lock/guard/status-update logic stays exactly as-is.

### 2.4 NestJS: `WorkflowService.advanceWorkflowStep`
This is where the location-requirement check belongs. Note: this is *not* mirroring an existing validation pattern — `src/jobs/workflow.service.ts:57-63, 173-182` is step-ordering guard logic (`validateStep()` and its `PT409`/422 raise on an out-of-order step), not a requirement-gating example. The code's own comment at `workflow.service.ts:50-52` states `requires_photo`/`requires_signature` are "frontend action gates, not chain filters" — they are parsed and echoed to the API response but never enforced server-side today. This feature introduces the first server-side per-step content validation in this method; it lives here because this is already where step-order guards live, not because it mirrors prior art:
1. Load the job's `capture_location_on_steps` and the target step's `requires_location`.
2. If both true: latitude/longitude must be present on the request and pass `hasInvalidCoordinates` range validation (reuse `validate-coordinates.ts`); if missing or invalid, follow CAP-4 — do not hard-fail the whole request; allow the advance to proceed and mark the omission (`p_location_captured: false, p_reason: ...`).
   - If a step requires both signature and location (see frontend-architecture.md 2.3), both captures must complete before this call is made — that ordering is a frontend concern, not something this method enforces.
3. Accuracy is never a gate: if `accuracy > 100` (meters), still pass the coordinates through but set `p_accuracy_flagged: true` so it surfaces for later review (decided — no hard-reject).
4. Pass validated coordinates (plus `p_location_captured`/`p_reason`/`p_accuracy_flagged` as applicable) through to the RPC call.

### 2.5 DTOs
- `CreateJobDto`: add `captureLocationOnSteps?: boolean` (defaults server-side to `true` if omitted). Both DTOs already decorate every field with `@ApiProperty`/`@ApiPropertyOptional` for Swagger — the new field needs the same, matching this DTO's existing style.
- `AdvanceWorkflowDto`: add `latitude?: number`, `longitude?: number`, `accuracy?: number` — validated with the same `@IsNumber() @Min/@Max` decorators as `StructuredAddressDto`, and `@ApiPropertyOptional()` on each (this DTO already decorates its one existing field, `step`, the same way).
- Job response DTOs: surface `captureLocationOnSteps` wherever a job is serialized (list + detail).

### 2.6 RLS
No new table, so no new RLS policy is needed — `activity_logs_tenant_isolation` already covers the metadata this feature adds.
