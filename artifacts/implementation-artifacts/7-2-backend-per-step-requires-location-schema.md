---
epic: 7
story_id: "7-2"
title: "Backend: per-step requires_location schema"
status: done
created: 2026-09-13
updated: 2026-09-13
acceptance_criteria:
  - AC1: "workflow_steps_valid() CHECK function accepts optional requires_location boolean per step, defaulting to true if absent"
  - AC2: "parseStep() TypeScript mirror updated with same default in the same commit"
  - AC3: "stepToResponse() maps requires_location → requiresLocation for API response"
  - AC4: "Existing workflow templates (no requires_location key) read as location-required via schema default"
  - AC5: "Both CHECK and parseStep mutations in single commit — verified by code review"
blocking:
  - "Must complete before starting frontend stories 7-5..7-9"
  - "Additive backend change ships before frontend consumes it"
spec_refs:
  - "spec-job-step-location-capture/SPEC.md CAP-3"
  - "spec-job-step-location-capture/backend-architecture.md section 2.2"
  - "spec-job-step-location-capture/stories.yaml id:2"
---

## Context

The workflow step schema currently supports `requires_photo` and `requires_signature` per step. This story extends it to support `requires_location` as an optional boolean that defaults to `true` (matching the product intent: required unless explicitly opted out).

The CHECK function and TypeScript parseStep() mirror **must** be updated in the same commit, or they silently drift.

## Approach

1. **Postgres Migration**: Update `workflow_steps_valid()` in the latest migration to validate `requires_location` (optional, boolean, defaults true if absent)
2. **TypeScript Mirror**: Update `parseStep()` in `src/jobs/workflow-template.model.ts` with identical default
3. **API Mapping**: Update `stepToResponse()` to surface `requires_location` → `requiresLocation` in the response
4. **Verification**: Code review confirms both functions carry the same default; no existing data migration needed (schema default handles it)

## Files to change

- `fenzit-be/supabase/migrations/`: Extend `workflow_steps_valid()` in the latest migration
- `fenzit-be/src/jobs/workflow-template.model.ts`: Update `parseStep()` and `stepToResponse()`

## Review Findings

- [ ] [Review][Patch] Template parsing default not guarded by test — add test verifying requires_location defaults to true when absent
- [ ] [Review][Patch] V1_TEMPLATE_STEPS lacks requires_location field — update test fixture to include requires_location declaration
