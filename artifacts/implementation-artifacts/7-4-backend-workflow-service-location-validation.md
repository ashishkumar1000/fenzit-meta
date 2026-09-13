---
epic: 7
story_id: "7-4"
title: "Backend: WorkflowService location validation"
status: in-progress
created: 2026-09-13
updated: 2026-09-13
acceptance_criteria:
  - AC1: "WorkflowService.advanceWorkflowStep loads job.capture_location_on_steps and target step's requires_location"
  - AC2: "When both true, validates lat/long range using hasInvalidCoordinates utility"
  - AC3: "Missing/invalid/low-accuracy location never hard-blocks step advance (CAP-4)"
  - AC4: "Accuracy > 100m flagged with accuracyFlagged: true but advance still succeeds"
  - AC5: "AdvanceWorkflowDto extended with optional latitude/longitude/accuracy fields"
  - AC6: "Location parameters passed to RPC with proper null-handling"
blocking:
  - "Done checkpoint: BE deploys before FE starts (per cross-repo ordering rule)"
spec_refs:
  - "spec-job-step-location-capture/backend-architecture.md section 2.4"
  - "spec-job-step-location-capture/stories.yaml id:4"
---

## Context

WorkflowService adds the first server-side per-step content validation. When a job requires location and a step requires location, coordinates are validated but never hard-blocked. Graceful failure handling ensures field work is never stalled.

## Changes

- Updated `src/jobs/workflow.service.ts`:
  - Imported hasInvalidCoordinates
  - Extended WorkflowJobRow interface with capture_location_on_steps
  - Updated fetch to include capture_location_on_steps
  - Added location validation logic (step 6.5) before RPC call
  - Pass validated coordinates to advance_workflow_step RPC

- Updated `src/jobs/dto/advance-workflow.dto.ts`:
  - Added optional latitude, longitude, accuracy fields
  - Decorated with @IsNumber(), @Min(), @Max() validators
  - Added @ApiPropertyOptional() descriptions

## Review Findings

- [ ] [Review][Patch] Falsy coordinate check rejects 0.0 as missing — change line 209 from `!dto.latitude || !dto.longitude` to explicit null/undefined check
- [ ] [Review][Patch] accuracy_flagged parameter coercion — change line 237 from `accuracyFlagged || null` to explicit ternary `accuracyFlagged ? true : null`
- [ ] [Review][Patch] accuracy field missing @Min(0) — add @Min(0) decorator to accuracy field in AdvanceWorkflowDto
- [ ] [Review][Patch] hasInvalidCoordinates function not verified — verify `src/common/utils/validate-coordinates` exists and `hasInvalidCoordinates` function is exported
- [ ] [Review][Patch] baseJobRow fixture missing capture_location_on_steps — add `capture_location_on_steps: true` to baseJobRow mock in workflow.service.spec.ts
- [ ] [Review][Patch] No E2E tests for location parameters — add E2E test cases for location capture scenarios (valid coords, invalid coords, accuracy flagging, low accuracy)
- [ ] [Review][Patch] Coordinate validation logic not tested — add service unit tests verifying hasInvalidCoordinates call rejects out-of-range coordinates
- [ ] [Review][Patch] Location parameters not asserted in RPC calls — update existing RPC call assertions in tests to verify location parameters passed
- [ ] [Review][Patch] Template parsing default not guarded by test — add unit test verifying parseStep defaults requires_location to true when absent
