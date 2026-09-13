---
id: SPEC-job-step-location-capture
companions: [backend-architecture.md, frontend-architecture.md]
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Technician Location Capture on Job Step Completion

## Why

Owners need proof that a technician was physically present when a job step was completed — a pain around accountability and dispute resolution that currently has no data behind it. Today `fenzit-be`/`fenzo-app` capture photos and signatures per step but never the technician's own GPS position. This is a mandate the owner wants configurable per job (not forced globally), landing now while the workflow-step engine (photo/signature requirements) is still young and can absorb one more per-step requirement type cleanly.

## Capabilities

- **CAP-1**
  - **intent:** Owner can configure, at job creation, whether the assigned technician must share GPS location while completing that job's steps.
  - **success:** NewJobScreen exposes a toggle (default ON); the created job persists `capture_location_on_steps` accordingly and the value round-trips on subsequent reads.

- **CAP-2**
  - **intent:** When a technician advances a workflow step that requires location (job toggle ON and the step is marked `requires_location`), they are prompted to capture their current GPS position, which is attached to the step-advance request.
  - **success:** For a job with capture enabled, completing a location-required step opens a capture flow (permission → GPS fetch) and the advance request carries latitude/longitude/accuracy; the resulting `activity_logs` row for that step contains the captured coordinates in `metadata`.

- **CAP-3**
  - **intent:** The workflow step schema supports per-step location requirements (`requires_location`) independent of the job-level toggle, so a future release can move from "one switch per job" to "owner configures per step" without another schema migration.
  - **success:** `workflow_templates.steps` JSONB accepts a `requires_location` boolean per step, validated by both the Postgres `workflow_steps_valid()` CHECK function and the TypeScript step parser; an absent `requires_location` key defaults to `true` (both in the CHECK function and the parser), so every existing and future seeded template requires location unless a step explicitly opts out.

- **CAP-4**
  - **intent:** Step completion is never blocked by location capture failure — permission denial, GPS unavailability, low-accuracy fix, or timeout must not stall field work.
  - **success:** Denying location permission, simulating a GPS timeout, or capturing a low-accuracy fix (>100m) all still allow the step-advance request to succeed; the resulting audit entry indicates location was not captured (or was low-accuracy) and records why.

## Constraints

- Must reuse the existing per-step "divert to a dedicated capture screen" pattern already used for signature capture (`useWorkflowAdvance.ts`: `requiresSignature` → navigate away before posting) — a `requiresLocation` step follows the identical divert-then-advance shape, not an inline capture.
- Must use `react-native-nitro-geolocation` (via its `/compat` API) — `fenzo-app` runs RN 0.86 with React Native's New Architecture enabled (`newArchEnabled=true`) and already depends on `react-native-nitro-modules` (via `react-native-mmkv`), so this adds no new native runtime. `react-native-geolocation-service` is bridge-only and unmaintained (last published ~4 years ago), a poor fit for this architecture; `expo-location` is unavailable (no Expo runtime).
- Location data is persisted via the existing `activity_logs.metadata` JSONB column on the per-step-advance insert already performed by `advance_workflow_step` — no new `step_completions` table.
- Any new workflow-step JSONB attribute (`requires_location`) must update BOTH the Postgres `workflow_steps_valid()` CHECK function AND the TypeScript `parseStep()` mirror in the same change, or the two silently disagree.
- Location-requirement validation (required? provided? valid range?) happens in NestJS `WorkflowService.advanceWorkflowStep` before the RPC call — `advance_workflow_step` performs no content validation today, and that division of responsibility must hold.
- No new offline-queue engine — reuse the existing per-action idempotency-key (`keyRef`) + inline-retry convention already in `useWorkflowAdvance.ts`, matching how other capture flows in this codebase currently defer offline handling (tagged `EPIC4`).
- The permission consent modal shows at most once per install — only while permission status is `undetermined`. Already-granted or already-denied states must never re-trigger it (denied → Settings redirect instead).
- GPS accuracy is never a hard-reject condition — a fix worse than 100m still lets the step advance; the low-accuracy fact is recorded in `activity_logs.metadata` (e.g. `accuracyFlagged: true`), not enforced as a gate.
- No location-specific data-retention/deletion policy is introduced by this feature — location fields inherit whatever retention (currently none) governs `activity_logs` as a whole; a bespoke policy is a separate, later concern if compliance requires it.

## Non-goals

- Geofence / distance-from-job-site validation. No reliable job coordinates exist yet (only the customer optionally has nullable lat/long) and no distance/haversine utility exists in the backend — deferred to a future spec.
- Per-step location configuration UI for owners. Backend supports it (CAP-3); MVP frontend only exposes the job-level toggle (CAP-1).
- An offline submission queue for location data — deferred, consistent with existing `EPIC4`-tagged deferrals elsewhere in the codebase.
- Continuous or background location tracking — capture is on-demand only, at the moment of step completion.
- An owner-facing UI to view captured location. This MVP is write-only: coordinates land in `activity_logs.metadata` but no screen (e.g. `ActivityTimeline.tsx`) renders them yet — a read-side viewer is future work.

## Success signal

An owner creates a job with the location toggle left at its default (ON). When the assigned technician advances a step that requires location, they are taken through a capture screen and, on success, the step advances with an `activity_logs` entry carrying their coordinates — stored as proof-of-presence in that job's activity trail for future retrieval (no owner-facing viewer ships in this MVP; see Non-goals). Turning the toggle OFF at creation means no step on that job ever prompts for location.

## Assumptions

None outstanding — both prior assumptions were confirmed as decisions (accept-with-warning accuracy handling; no bespoke retention policy) and are now reflected in Constraints.

## Open Questions

None outstanding.
