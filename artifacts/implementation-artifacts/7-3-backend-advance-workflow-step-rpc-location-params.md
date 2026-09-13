---
epic: 7
story_id: "7-3"
title: "Backend: advance_workflow_step RPC accepts location"
status: in-progress
created: 2026-09-13
updated: 2026-09-13
acceptance_criteria:
  - AC1: "RPC signature extended with 6 optional parameters: p_latitude, p_longitude, p_accuracy, p_location_captured, p_reason, p_accuracy_flagged"
  - AC2: "activity_logs metadata insert merges location data when coordinates present"
  - AC3: "Partial lat/long pair (one set, one NULL) treated as no coordinates"
  - AC4: "jsonb_strip_nulls removes stray null fields from metadata object"
  - AC5: "No other RPC logic changes — lock/guard/status-update stays identical"
blocking:
  - "Must complete before starting frontend stories 7-5..7-9"
spec_refs:
  - "spec-job-step-location-capture/backend-architecture.md section 2.3"
  - "spec-job-step-location-capture/stories.yaml id:3"
---

## Context

The advance_workflow_step RPC is extended to accept location data as six optional parameters. These are merged into the activity_logs metadata via jsonb_build_object with safeguards against partial coordinates and null fields.

## Changes

- New migration: `20260913000002_advance_workflow_step_location_params.sql`
  - Updated RPC signature with 6 new optional parameters
  - Extended activity_logs INSERT with CASE logic to handle coordinate pairs
  - Guard against partial lat/long using jsonb_strip_nulls

## Review Findings

- [ ] [Review][Patch] RPC parameter documentation sparse — add inline parameter documentation to RPC function
